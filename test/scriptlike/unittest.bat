@echo off
rdmd -unittest --force -gc -debug -ofbin\scriptlike_unittest -version=unittest_scriptlike_d -Isrc src\scriptlike\package.d
