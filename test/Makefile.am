NULL = 

AM_CFLAGS = \
	$(OORT_CFLAGS) \
	-include $(CONFIG_HEADER) \
	-I $(top_srcdir)/vector \
	-I $(top_srcdir)/sim \
	-I $(top_srcdir)/luajit/src \
	-include oort.h \
	$(NULL)

AM_VALAFLAGS = \
	--pkg oort \
	--pkg lua \
	--pkg vector \
	--pkg util \
	--pkg gio-2.0 \
	--vapidir $(top_srcdir)/vapi \
	--vapidir $(top_srcdir)/vector \
	--vapidir $(top_srcdir)/sim \
	$(NULL)

LIBS=$(OORT_LIBS) -lm

TESTS = test_syntax_errors
check_PROGRAMS = test_syntax_errors
test_syntax_errors_SOURCES = test_syntax_errors.vala
test_syntax_errors_LDADD = $(top_srcdir)/sim/libsim.a $(top_srcdir)/cjson/libcjson.a $(top_srcdir)/luajit/src/libluajit.a
test_syntax_errors_LDFLAGS = $(OORT_EXTRA_LDFLAGS)

EXTRA_DIST = \
	ai/syntax_error.lua \
	scenarios/syntax_error.json \
	scenarios/simple.json \
	$(NULL)
