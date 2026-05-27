#---------------------------------------------------------------------------------
# Clear the implicit built in rules
#---------------------------------------------------------------------------------
.SUFFIXES:
#---------------------------------------------------------------------------------

.DEFAULT_GOAL := all

.PHONY: samples check-deps doctor

check-deps:
	@sh tools/check-deps.sh

doctor: check-deps

all: check-deps
	@$(MAKE_COMMAND) -C ppu --no-print-directory
	@$(MAKE_COMMAND) -C spu --no-print-directory
	@$(MAKE_COMMAND) -C common --no-print-directory
	@$(MAKE_COMMAND) -C tools --no-print-directory

samples:
	@$(MAKE_COMMAND) -C samples --no-print-directory

doc:
	@doxygen doxygen.conf

install-ctrl:
	@[ -d $(PSL1GHT) ] || mkdir -p $(PSL1GHT)
	@cp -frv base_rules $(PSL1GHT)
	@cp -frv ppu_rules  $(PSL1GHT)
	@cp -frv spu_rules  $(PSL1GHT)
	@cp -frv data_rules $(PSL1GHT)

install-socat:
	@$(MAKE_COMMAND) -C tools install-socat --no-print-directory

install: check-deps
	@$(MAKE_COMMAND) -C ppu install --no-print-directory
	@$(MAKE_COMMAND) -C spu install --no-print-directory
	@$(MAKE_COMMAND) -C common install --no-print-directory
	@$(MAKE_COMMAND) -C tools install --no-print-directory

clean:
	@$(MAKE_COMMAND) -C ppu clean --no-print-directory
	@$(MAKE_COMMAND) -C spu clean --no-print-directory
	@$(MAKE_COMMAND) -C common clean --no-print-directory
	@$(MAKE_COMMAND) -C tools clean --no-print-directory
	@rm -rf doc

.PHONY: all clean install install-ctrl install-socat doc
