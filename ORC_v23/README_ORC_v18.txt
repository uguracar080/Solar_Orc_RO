ORC_v18
=======

Purpose
-------
V0.19 keeps the v0.17 thermodynamic, STHE sizing, fixed-geometry rating and
dispatch physics unchanged.  It adds explicit property-cache diagnostics for
design, fixed-geometry rating and dispatch stages.

Changes from V0.17
------------------
1) orc_properties.m now supports private diagnostic commands:

   orc_properties(config,'CACHERESET')
   orc_properties(config,'CACHESTATS')

   CACHESTATS returns request, hit, miss, store, bypass, reset and current-entry
   counters plus cache hit rates.

2) The default property-cache maximum size is increased:

   config.orc_property_cache_maxEntries = 250000;

   This avoids silent whole-cache resets during long dispatch stress tests.

3) orc_quickstart.m resets the property cache at the beginning by default:

   config.orc_property_cache_resetAtQuickstart = true;

   and prints a final ORC PROPERTY CACHE SUMMARY block.

4) orc_stage2_dispatch_test_suite.m prints dispatch-block cache usage:

   Cache req/hit/miss
   Cache hit rate
   Cache entries
   Cache resets

Notes
-----
All ORC working-fluid and external-stream property calls that pass through
orc_properties/orc_stream_properties share the same persistent cache.  This
includes Stage-1, Stage-2 forced rating and Stage-2 dispatch.  The cache is
exact-key based, so it is most useful when the same pressure/temperature/quality
states repeat across candidate operating points.
