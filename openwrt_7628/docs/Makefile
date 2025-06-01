SPHINXBUILD   = sphinx-build
SOURCEDIR     = source
BUILDDIR      = build

html:
	@$(SPHINXBUILD) -b html "$(SOURCEDIR)" "$(BUILDDIR)/html"

pdf:
	@$(SPHINXBUILD) -b latex "$(SOURCEDIR)" "$(BUILDDIR)/latex"
	@make -C "$(BUILDDIR)/latex" all-pdf

clean:
	rm -rf $(BUILDDIR)/*

.PHONY: html pdf clean
