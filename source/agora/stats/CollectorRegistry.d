/*******************************************************************************

    Contains a collection of prometheus stat collectors that acts as an
    interface between the response handler, and stat collectors from every
    individual metric and label set.

    Copyright:
        Copyright (c) 2019 dunnhumby Germany GmbH.
        All rights reserved

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module agora.stats.CollectorRegistry;

import agora.stats.Collector : Collector;

version (unittest) import std.algorithm;

/// ditto
public class CollectorRegistry
{
    /// An alias for the type of delegates that are called for stat collection
    public alias void delegate ( Collector ) CollectionDg;

    /// An array of delegates that are called for stat collection
    private CollectionDg[] collector_callbacks;

    /// The collector to use for stat collection. This acts as the actual
    /// parameter for the delegates in `collector_callbacks`.
    private Collector collector;

    /***************************************************************************

        Constructor, that accepts an array of stat collection callbacks.

        Params:
            callbacks = An array of delegates to be called for stat collection.

    ***************************************************************************/

    public this ( scope CollectionDg[] callbacks )
    {
        this.collector = new Collector();
        this.collector_callbacks = callbacks;
    }

    /***************************************************************************

        Appends a stat collector callback to the list of existing ones.
        May result in a re-allocation of the entire buffer storing the
        callbacks.

        Params:
            collector = The stat collector to append.

    ***************************************************************************/

    public void addCollector ( scope CollectionDg collector )
    {
        this.collector_callbacks ~= collector;
    }

    /***************************************************************************

        Collects stats by calling all delegates specified for stat collection,
        formats them using `ocean.util.prometheus.collector.StatFormatter`
        eventually, and finally returns the accumulated result. The
        specifications of the format can be found at
        `https://prometheus.io/docs/instrumenting/exposition_formats/`.

        Returns:
            The stats accumulated since last time this method was called.

    ***************************************************************************/

    public const(char)[] collect ( )
    {
        import core.time;
        import std.format;
        auto start = MonoTime.currTime;
        this.collector.reset();

        try
        {
            foreach (ref callback; this.collector_callbacks)
            {
                callback(this.collector);
            }
        }
        catch (Exception ex)
        {
            throw ex;
        }

        return this.collector.getCollection() ~
            format("scrape_duration_ms %s", (MonoTime.currTime - start).total!"msecs");
    }
}

version (unittest)
{
    import agora.stats.Collector;

    import agora.stats.StatFormatter : Labels, Statistics;

    private class ExampleStats
    {
        Statistics test_stats;
        Labels test_labels;

        ///
        public void setTestStats ( Statistics stats )
        {
            test_stats = stats;
        }

        ///
        public void setTestLabels ( Labels labels )
        {
            test_labels = labels;
        }

        ///
        public void collectDg1 ( Collector collector )
        {
            collector.collect!("id")(test_stats, 123.034);
        }

        ///
        public void collectDg2 ( Collector collector )
        {
            collector.collect(test_stats, test_labels);
        }
    }
}

/// Test collection from a single delegate
unittest
{
    auto stats = new ExampleStats();
    auto registry = new CollectorRegistry([&stats.collectDg1]);

    stats.setTestStats(Statistics(3600, 347, 3.14, 6.023, 0.43));

    assert(registry.collect().startsWith(
        "up_time_s {id=\"123.034\"} 3600\ncount {id=\"123.034\"} 347\n" ~
        "ratio {id=\"123.034\"} 3.14\nfraction {id=\"123.034\"} 6.023\n" ~
        "very_real {id=\"123.034\"} 0.43\n"));
}

/// Test collection from more than one delegates
unittest
{
    auto stats = new ExampleStats();
    auto registry = new CollectorRegistry([&stats.collectDg1]);
    registry.addCollector(&stats.collectDg2);

    stats.setTestStats(Statistics(3600, 347, 3.14, 6.023, 0.43));
    stats.setTestLabels(Labels(1_235_813, "ocean", 3.14159));

    assert(registry.collect().startsWith(
        "up_time_s {id=\"123.034\"} 3600\ncount {id=\"123.034\"} 347\n" ~
        "ratio {id=\"123.034\"} 3.14\nfraction {id=\"123.034\"} 6.023\n" ~
        "very_real {id=\"123.034\"} 0.43\n" ~

        "up_time_s {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 3600\n" ~
        "count {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 347\n" ~
        "ratio {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 3.14\n" ~
        "fraction {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 6.023\n" ~
        "very_real {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 0.43\n"));
}

/// Test that the collections are not accumulated upon more than one call to
/// the `collect` method.
unittest
{
    auto stats = new ExampleStats();
    auto registry = new CollectorRegistry([&stats.collectDg2]);

    stats.setTestStats(Statistics(3600, 347, 3.14, 6.023, 0.43));
    stats.setTestLabels(Labels(1_235_813, "ocean", 3.14159));

    auto collected = registry.collect();

    // Update the stats
    stats.setTestStats(Statistics(4200, 257, 2.345, 1.098, 0.56));

    // A 2nd call to `collect` should return the updated stats, without the
    // previous values anywhere in it.
    assert(registry.collect(),
        "up_time_s {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 4200\n" ~
        "count {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 257\n" ~
        "ratio {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 2.345\n" ~
        "fraction {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 1.098\n" ~
        "very_real {id=\"1235813\",job=\"ocean\",perf=\"3.14159\"} 0.56\n");
}
