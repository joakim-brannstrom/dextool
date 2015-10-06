
all: test examples

DOCOPTLIB = libdocopt.a

DMDLINK = -Isource -L$(DOCOPTLIB)

DFLAGS = -debug

$(DOCOPTLIB): source/*.d
	dmd -lib -oflibdocopt.a source/*.d

test/test_docopt: $(DOCOPTLIB)
	dmd $(DFLAGS) test/test_docopt.d -oftest/test_docopt $(DMDLINK)

test: test/test_docopt
	dub test
	./test/test_docopt test/testcases.docopt

examples: arguments

arguments: examples/arguments/source/arguments.d $(DOPOPTLIB)
	dmd $(DFLAGS) examples/arguments/source/arguments.d -op $(DMDLINK)

git: gitD git_add git_branch git_checkout git_clone git_commit git_push git_remote

gitD: examples/git/gitD.d $(DOCOPTLIB)
	dmd $(DFLAGS) $< -op $(DMDLINK)

git_add: examples/git/git_add.d $(DOCOPTLIB)
	dmd $(DFLAGS) $< -op $(DMDLINK)

git_branch: examples/git/git_branch.d $(DOCOPTLIB)
	dmd $(DFLAGS) $< -op $(DMDLINK)

git_checkout: examples/git/git_checkout.d $(DOCOPTLIB)
	dmd $(DFLAGS) $< -op $(DMDLINK)

git_clone: examples/git/git_clone.d $(DOCOPTLIB)
	dmd $(DFLAGS) $< -op $(DMDLINK)

git_commit: examples/git/git_commit.d $(DOCOPTLIB)
	dmd $(DFLAGS) $< -op $(DMDLINK)

git_push: examples/git/git_push.d $(DOCOPTLIB)
	dmd $(DFLAGS) $< -op $(DMDLINK)

git_remote: examples/git/git_remote.d $(DOCOPTLIB)
	dmd $(DFLAGS) $< -op $(DMDLINK)

clean:
	@rm -rf test/test_docopt test/test_docopt.o
	@rm -rf lib*a
	@rm -rf __test__library__
	@rm -rf arguments
	@rm -rf gitD git_add git_branch git_checkout git_clone git_commit git_push git_remote
	@find . -name "*.o" -exec rm {} \;

.PHONY: git test
