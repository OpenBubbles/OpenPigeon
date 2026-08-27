package com.openbubbles.openpigeon.knockout

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class KnockoutWaterView(context: Context) : GLSurfaceView(context) {

    private val renderer = WaterRenderer()

    init {
        setEGLContextClientVersion(2)
        setRenderer(renderer)
        renderMode = RENDERMODE_CONTINUOUSLY
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

    private class WaterRenderer : Renderer {
        @Volatile
        var useTint = false
        @Volatile
        var tintR = 1.0f
        @Volatile
        var tintG = 1.0f
        @Volatile
        var tintB = 1.0f

        private var program = 0
        private var aPos = 0
        private var aTex = 0
        private var uTime = 0
        private var uX = 0
        private var uAspect = 0
        private var startNs = 0L
        private var uTint = 0
        private var uUseTint = 0
        private var aspect = 1f

        private val quad: FloatBuffer = run {
            // posX, posY, texU, texV  (triangle strip: BL, BR, TL, TR)
            val d = floatArrayOf(
                -1f, -1f, 0f, 1f, 1f, -1f, 1f, 1f, -1f, 1f, 0f, 0f, 1f, 1f, 1f, 0f
            )
            ByteBuffer.allocateDirect(d.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
                .apply { put(d); position(0) }
        }

        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            GLES20.glClearColor(0.667f, 0.851f, 0.969f, 1f) // #AAD9F7 base, in case of any gap
            program = buildProgram(VERTEX_SRC, FRAGMENT_SRC)
            aPos = GLES20.glGetAttribLocation(program, "aPos")
            aTex = GLES20.glGetAttribLocation(program, "aTex")
            uTime = GLES20.glGetUniformLocation(program, "u_time")
            uX = GLES20.glGetUniformLocation(program, "u_x")
            uAspect = GLES20.glGetUniformLocation(program, "uAspect")
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

        private fun buildProgram(vs: String, fs: String): Int {
            val p = GLES20.glCreateProgram()
            GLES20.glAttachShader(p, compile(GLES20.GL_VERTEX_SHADER, vs))
            GLES20.glAttachShader(p, compile(GLES20.GL_FRAGMENT_SHADER, fs))
            GLES20.glLinkProgram(p)
            val ok = IntArray(1); GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, ok, 0)
            if (ok[0] == 0) {
                val log = GLES20.glGetProgramInfoLog(p); GLES20.glDeleteProgram(p)
                throw RuntimeException("Water link failed: $log")
            }
            return p
        }

        private fun compile(type: Int, src: String): Int {
            val s = GLES20.glCreateShader(type)
            GLES20.glShaderSource(s, src); GLES20.glCompileShader(s)
            val ok = IntArray(1); GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, ok, 0)
            if (ok[0] == 0) {
                val log = GLES20.glGetShaderInfoLog(s); GLES20.glDeleteShader(s)
                throw RuntimeException("Water compile failed: $log")
            }
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
        private const val FRAGMENT_SRC = """
            precision highp float;
            varying vec2 v_tex_coord;
            uniform float u_time;
            uniform float u_x;
            uniform vec3 u_tint;
            uniform float u_use_tint;

            const float CREST_LOW = 0.72;
            const float CREST_HIGH = 1.0;
            const vec3 DEEP = vec3(0.165, 0.524, 0.871);
            const vec3 ICE = vec3(0.58, 0.80, 0.97);

            float wav(vec2 q) {
                return (sin(q.x + q.y * 0.7) + 0.6 * sin(q.x * -2.1 + q.y * 1.7)) * 0.625;
            }
            float fbm(vec2 q) {
                float n = sin(q.x + q.y * 0.7);
                n += 0.55 * sin(q.x * -2.3 + q.y * 1.9);
                n += 0.30 * sin(q.x * 4.1 + q.y * 3.3);
                return n * 0.54;
            }

            void main(void){
                float t = u_time;
                vec2 uv = vec2(v_tex_coord.x + u_x, v_tex_coord.y);

                vec2 q = vec2(uv.x * 18.0 - t * 2.0, uv.y * 42.0);

                vec2 warp = vec2(
                    wav(q * 0.28 + vec2(t * 0.5, 0.0)),
                    wav(q * 0.45 + vec2(7.3, 3.1) - vec2(t * 0.3, 0.0))
                );

                float n1 = fbm(q + warp * 1.8);
                float n2 = fbm(q * 2.7 + warp * 2.2 - vec2(t * 3.0, 0.0));

                float ridge = (1.0 - abs(n1)) * 0.82 + (1.0 - abs(n2)) * 0.18;
                float crest = smoothstep(CREST_LOW, CREST_HIGH, ridge);
                float swell = n1 * 0.5 + 0.5;

                vec3 col2 = mix(DEEP * (0.97 + swell * 0.05), ICE, crest * 0.30);

                float lum = dot(col2, vec3(0.299, 0.587, 0.114));
                vec3 tinted = u_tint * (0.72 + (lum - 0.55) * 1.15);
                vec3 finalColor = mix(col2, tinted, u_use_tint);
                gl_FragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
            }
        """
    }
}