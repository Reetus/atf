# atf - run a command at a specified time, in the foreground
#
# Targets:
#   make            build ./atf (dynamic)
#   make static     build a fully static ./atf (no runtime dependencies)
#   make test       run the functional test suite against ./atf
#   make test-static  rebuild static and run the suite
#   make install    install to $(PREFIX)/bin (default /usr/local)
#   make clean

VERSION := 0.1.0
BUILD := build
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

VENDOR_DIR := third_party/parse-datetime
COMPAT_DIR := third_party/compat
VENDOR_CPPFLAGS := -I$(VENDOR_DIR) -I$(COMPAT_DIR)

CFLAGS ?= -O2
CXXFLAGS ?= -O2
override CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -Wno-sign-compare
override CXXFLAGS += -std=c++17 -Wall -Wextra -DATF_VERSION=\"$(VERSION)\"

ifdef STATIC
LDFLAGS += -static
endif

OBJS := $(BUILD)/parse-datetime.o $(BUILD)/c-ctype.o $(BUILD)/gettime.o \
        $(BUILD)/compat.o $(BUILD)/atf.o

.PHONY: all static test test-static install uninstall clean

all: atf

atf: $(OBJS)
	$(CXX) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

$(BUILD)/%.o: $(VENDOR_DIR)/%.c | $(BUILD)
	$(CC) $(VENDOR_CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: $(COMPAT_DIR)/%.c | $(BUILD)
	$(CC) $(VENDOR_CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: src/%.cpp | $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD):
	mkdir -p $@

static:
	$(MAKE) clean
	$(MAKE) STATIC=1 all

test: atf
	./tests/run.sh ./atf

test-static: static
	./tests/run.sh ./atf

install: atf
	install -Dm755 atf $(DESTDIR)$(BINDIR)/atf

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/atf

clean:
	rm -rf $(BUILD) atf
