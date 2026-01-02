# Makefile for converting Markdown documentation to PDF using Pandoc

# --- Configuration ---
# Directory where the documentation source files and PDFs are located.
DOC_DIR := docs
EXAMPLES_DIR := examples

# Pandoc command with flags.
# --pdf-engine=xelatex: A modern engine that handles Unicode well.
# --highlight-style=tango: A popular and readable style for syntax highlighting.
# -V monofont="DejaVu Sans Mono": Specifies a monospaced font for code blocks.
# -V mainfont="DejaVu Sans": Specifies the main font for the document body.
# -V geometry:margin=0.75in: Sets the page margins to 0.75 inches, giving more
#   horizontal space to prevent ugly wrapping in code blocks.
PANDOC := pandoc --pdf-engine=xelatex --highlight-style=tango -V mainfont="DejaVu Sans" -V monofont="DejaVu Sans Mono" -V geometry:margin=0.75in

# --- File Definitions ---
# Find all .md files in the docs directory.
DOC_SOURCES := $(wildcard $(DOC_DIR)/*.md)

# Create a list of target PDF files by replacing the .md extension with .pdf.
DOC_PDFS := $(patsubst %.md,%.pdf,$(DOC_SOURCES))

# Likewise for examples
EXAMPLES_SOURCES := $(wildcard $(EXAMPLES_DIR)/*.md)
EXAMPLES_PDFS    := $(patsubst %.md,%.pdf,$(EXAMPLES_SOURCES))

# Define the root README source and its target PDF location.
ROOT_README_SRC := README.md
ROOT_README_PDF := $(DOC_DIR)/README.pdf

# --- OS-specific commands for 'clean' target ---
# Use 'del' on Windows and 'rm' on other systems for cleaning up files.
# This makes the Makefile cross-platform.
ifeq ($(OS),Windows_NT)
    # The 'subst' function replaces forward slashes with backslashes for Windows compatibility.
    # The '2>nul' part suppresses "file not found" errors if files don't already exist.
    CLEAN = del /F /Q $(subst /,\,$(DOC_PDFS) $(EXAMPLES_PDFS) $(ROOT_README_PDF)) 2>nul
else
    CLEAN = rm -f $(DOC_PDFS) $(ROOT_README_PDF) $(EXAMPLES_PDFS)
endif


# --- Targets ---

# The 'all' target is the default. It depends on all the PDF files that need to be created.
# Typing 'make' or 'make all' will build everything.
.PHONY: all
all: $(DOC_PDFS) $(ROOT_README_PDF) $(EXAMPLES_PDFS)

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

# Likewise for the examples/ directory
$(EXAMPLES_DIR)/%.pdf: $(EXAMPLES_DIR)/%.md
	@echo "Building $@ from $<..."
	@$(PANDOC) $< -o $@


# The 'clean' target removes all generated PDF files.
# This is useful for starting a fresh build.
.PHONY: clean
clean:
	@echo "Cleaning up generated PDF files..."
	@$(CLEAN)


