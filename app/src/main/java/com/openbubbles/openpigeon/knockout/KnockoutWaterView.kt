package com.openbubbles.openpigeon.knockout

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.GLUtils
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class KnockoutWaterView(context: Context) : GLSurfaceView(context) {

    private val renderer = WaterRenderer(context)

    init {
        setEGLContextClientVersion(2)
        setRenderer(renderer)
        renderMode = RENDERMODE_CONTINUOUSLY
    }

    fun setWaterTexture(assetPath: String) {
        renderer.assetPath = assetPath
    }

    fun setTint(r: Float, g: Float, b: Float) {
        queueEvent {
            renderer.useTint = true
            renderer.tintR = r
            renderer.tintG = g
            renderer.tintB = b
        }
    }

    fun clearTint() {
        queueEvent {
            renderer.useTint = false
            renderer.tintR = 1.0f
            renderer.tintG = 1.0f
            renderer.tintB = 1.0f
        }
    }

    private class WaterRenderer(private val context: Context) : Renderer {
        var assetPath = "knockout/water.png"

        @Volatile var useTint = false
        @Volatile var tintR = 1.0f
        @Volatile var tintG = 1.0f
        @Volatile var tintB = 1.0f

        private var program = 0
        private var aPos = 0; private var aTex = 0
        private var uTime = 0; private var uX = 0
        private var uTexture = 0; private var uAspect = 0
        private var textureId = 0
        private var startNs = 0L
        private var uTint = 0
        private var uUseTint = 0
        private var aspect = 1f

        private val quad: FloatBuffer = run {
            // posX, posY, texU, texV  (triangle strip: BL, BR, TL, TR)
            val d = floatArrayOf(
                -1f, -1f, 0f, 1f,
                1f, -1f, 1f, 1f,
                -1f,  1f, 0f, 0f,
                1f,  1f, 1f, 0f
            )
            ByteBuffer.allocateDirect(d.size * 4).order(ByteOrder.nativeOrder())
                .asFloatBuffer().apply { put(d); position(0) }
        }

        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            GLES20.glClearColor(0.667f, 0.851f, 0.969f, 1f) // #AAD9F7 base, in case of any gap
            program = buildProgram(VERTEX_SRC, FRAGMENT_SRC)
            aPos = GLES20.glGetAttribLocation(program, "aPos")
            aTex = GLES20.glGetAttribLocation(program, "aTex")
            uTime = GLES20.glGetUniformLocation(program, "u_time")
            uX = GLES20.glGetUniformLocation(program, "u_x")
            uTexture = GLES20.glGetUniformLocation(program, "u_texture")
            uAspect = GLES20.glGetUniformLocation(program, "uAspect")
            textureId = loadTexture(assetPath)
            startNs = System.nanoTime()
            uTint = GLES20.glGetUniformLocation(program, "u_tint")
            uUseTint = GLES20.glGetUniformLocation(program, "u_use_tint")
        }

        override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
            GLES20.glViewport(0, 0, width, height)
            aspect = if (width > 0) height.toFloat() / width.toFloat() else 1f
        }

        override fun onDrawFrame(gl: GL10?) {
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            if (program == 0) return
            GLES20.glUseProgram(program)

            GLES20.glUniform1f(uTime, (System.nanoTime() - startNs) / 1_000_000_000f)
            GLES20.glUniform1f(uX, 0f)
            GLES20.glUniform3f(uTint, tintR, tintG, tintB)
            GLES20.glUniform1f(uUseTint, if (useTint) 1.0f else 0.0f)
            GLES20.glUniform1f(uAspect, aspect)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, textureId)
            GLES20.glUniform1i(uTexture, 0)

            quad.position(0)
            GLES20.glVertexAttribPointer(aPos, 2, GLES20.GL_FLOAT, false, 16, quad)
            GLES20.glEnableVertexAttribArray(aPos)
            quad.position(2)
            GLES20.glVertexAttribPointer(aTex, 2, GLES20.GL_FLOAT, false, 16, quad)
            GLES20.glEnableVertexAttribArray(aTex)

            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)

            GLES20.glDisableVertexAttribArray(aPos)
            GLES20.glDisableVertexAttribArray(aTex)
        }

        private fun loadTexture(path: String): Int {
            val ids = IntArray(1); GLES20.glGenTextures(1, ids, 0)
            val id = ids[0]
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_REPEAT)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_REPEAT)
            val opts = BitmapFactory.Options().apply { inScaled = false }
            val bmp: Bitmap = context.assets.open(path).use { BitmapFactory.decodeStream(it, null, opts) }!!
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bmp, 0)
            bmp.recycle()
            return id
        }

        private fun buildProgram(vs: String, fs: String): Int {
            val p = GLES20.glCreateProgram()
            GLES20.glAttachShader(p, compile(GLES20.GL_VERTEX_SHADER, vs))
            GLES20.glAttachShader(p, compile(GLES20.GL_FRAGMENT_SHADER, fs))
            GLES20.glLinkProgram(p)
            val ok = IntArray(1); GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, ok, 0)
            if (ok[0] == 0) { val log = GLES20.glGetProgramInfoLog(p); GLES20.glDeleteProgram(p)
                throw RuntimeException("Water link failed: $log") }
            return p
        }

        private fun compile(type: Int, src: String): Int {
            val s = GLES20.glCreateShader(type)
            GLES20.glShaderSource(s, src); GLES20.glCompileShader(s)
            val ok = IntArray(1); GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, ok, 0)
            if (ok[0] == 0) { val log = GLES20.glGetShaderInfoLog(s); GLES20.glDeleteShader(s)
                throw RuntimeException("Water compile failed: $log") }
            return s
        }
    }

    companion object {
        private const val VERTEX_SRC = """
            attribute vec2 aPos;
            attribute vec2 aTex;
            uniform float uAspect;
            varying vec2 v_tex_coord;
            void main() {
                v_tex_coord = vec2(aTex.x, aTex.y * uAspect);
                gl_Position = vec4(aPos, 0.0, 1.0);
            }
        """

        // Verbatim water3.fsh + the three globals SpriteKit injects automatically.
        private const val FRAGMENT_SRC = """
            precision highp float;
            varying vec2 v_tex_coord;
            uniform sampler2D u_texture;
            uniform float u_time;
            uniform float u_x;
            uniform vec3 u_tint;
            uniform float u_use_tint;

            vec3 rgb2hsv(vec3 c){
                vec4 K = vec4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
                vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
                vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
                float d = q.x - min(q.w, q.y);
                float e = 1.0e-10;
                return vec3(abs(q.z + (q.w - q.y)/(6.0*d+e)), d/(q.x+e), q.x);
            }
            vec3 hsv2rgb(vec3 c){
                vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
                vec3 p = abs(fract(c.xxx + K.xyz)*6.0 - K.www);
                return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
            }
            float mirror_repeat(float v) {
                float m = mod(v, 2.0);
                return 1.0 - abs(m - 1.0);
            }
            
            vec2 mo(vec2 m) {
                return vec2(mirror_repeat(m.x), mirror_repeat(m.y));
            }

            void main(void){
                float amp = 1.2;
                float time = u_time;
                vec2 uv = vec2(v_tex_coord.x + u_x, v_tex_coord.y);
                vec2 p = uv + mo(-(texture2D(u_texture, mo((uv*0.3) + vec2(time*0.04, 0.0))).xy)*amp +
                                  (texture2D(u_texture, uv*0.3 - vec2(time*0.05, 0.0)).xy)*amp);
                vec4 val = texture2D(u_texture, mo(p));
                vec3 col = rgb2hsv(vec3(val.r, val.g, val.b));
                col.x -= 7.0/255.0;
                col.y -= 0.35;
                col.z += 0.117;
                vec3 col2 = hsv2rgb(vec3(col.x, col.y, col.z));
                float lum = dot(col2, vec3(0.299, 0.587, 0.114));
                vec3 tinted = u_tint * (0.72 + (lum - 0.55) * 1.15);
                vec3 finalColor = mix(col2, tinted, u_use_tint);
                gl_FragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
            }
        """
    }
}