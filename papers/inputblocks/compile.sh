#!/bin/bash

# Compile LaTeX document to PDF

# Check if llncs.cls exists, copy if needed
if [ ! -f "llncs.cls" ]; then
    if [ -f "../contractual/llncs.cls" ]; then
        cp ../contractual/llncs.cls .
        echo "Copied llncs.cls from contractual directory"
    else
        echo "Error: llncs.cls not found. Please download LLNCS class file."
        exit 1
    fi
fi

# Compile LaTeX document
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex

# Clean up auxiliary files
rm -f main.aux main.log main.out main.toc main.bbl main.blg

echo "Compilation complete. Output: main.pdf"