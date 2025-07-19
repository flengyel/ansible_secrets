# Makefile for converting Markdown documentation to PDF using Pandoc

# --- Configuration ---
# Directory where the documentation source files and PDFs are located.
DOC_DIR := docs

# Pandoc command with flags.
# --pdf-engine=xelatex: A modern engine that handles Unicode (and thus a wide range of characters) well.
# --highlight-style=tango: A popular and readable style for syntax highlighting in code blocks.
PANDOC := pandoc --pdf-engine=xelatex --highlight-style=tango

# --- File Definitions ---
# Find all .md files in the docs directory.
DOC_SOURCES := $(wildcard $(DOC_DIR)/*.md)

# Create a list of target PDF files by replacing the .md extension with .pdf.
DOC_PDFS := $(patsubst %.md,%.pdf,$(DOC_SOURCES))

# Define the root README source and its target PDF location.
ROOT_README_SRC := README.md
ROOT_README_PDF := $(DOC_DIR)/README.pdf

# --- Targets ---

# The 'all' target is the default. It depends on all the PDF files that need to be created.
# Typing 'make' or 'make all' will build everything.
.PHONY: all
all: $(DOC_PDFS) $(ROOT_README_PDF)

# Rule for converting the root README.md to docs/README.pdf.
$(ROOT_README_PDF): $(ROOT_README_SRC)
	@echo "Building $@ from $<..."
	@$(PANDOC) $< -o $@

# Pattern rule to convert any .md file in the docs/ directory to its corresponding .pdf file.
# $< is the input file (the .md file).
# $@ is the output file (the .pdf file).
$(DOC_DIR)/%.pdf: $(DOC_DIR)/%.md
	@echo "Building $@ from $<..."
	@$(PANDOC) $< -o $@

# The 'clean' target removes all generated PDF files.
# This is useful for starting a fresh build.
.PHONY: clean
clean:
	@echo "Cleaning up generated PDF files..."
	@rm -f $(DOC_PDFS) $(ROOT_README_PDF)

