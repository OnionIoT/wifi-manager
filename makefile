SRCEXT := sh
SRCDIR := .
SOURCES := $(shell find $(SRCDIR) -type f -name *.$(SRCEXT))

DST := $(shell echo $(SOURCES) | sed -e 's/\.$(SRCEXT)//')

all: copy

copy:
	@echo $(SOURCES)

clean:
	@rm -rf $(DST)
