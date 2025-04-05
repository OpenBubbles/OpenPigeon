package com.example.openbubblesextension.wordhunt

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.example.openbubblesextension.R

class FoundWordsAdapter(private val wordsList: List<String>) :
    RecyclerView.Adapter<FoundWordsAdapter.WordViewHolder>() {

    class WordViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val wordText: TextView = itemView.findViewById(R.id.wordText)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): WordViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.wordhunt_found_word, parent, false)
        return WordViewHolder(view)
    }

    override fun onBindViewHolder(holder: WordViewHolder, position: Int) {
        val word = wordsList[position]
        holder.wordText.text = word
    }

    override fun getItemCount(): Int = wordsList.size
}