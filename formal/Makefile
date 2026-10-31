# Formal check of the icache against an uncached memory (SymbiYosys, yices).
RTL := ../rtl
icache.v: $(RTL)/ysyx_00000000_pkg.sv $(RTL)/ysyx_00000000_ICache.sv
	sv2v -DSYNTHESIS $^ > $@

icache: icache.v icache_check.v icache.sby
	timeout 3600 sby -f icache.sby prove cover

clean:
	rm -rf icache.v icache_bmc icache_cover

.PHONY: icache clean
