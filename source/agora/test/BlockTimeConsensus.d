/*******************************************************************************

    Tests the consensus algorithm on block time offset creation

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.BlockTimeConsensus;

version (unittest):

import agora.test.Base;

///
unittest
{
    TestConf conf;
    conf.consensus.block_interval = 2.seconds;
    auto network = makeTestNetwork!TestAPIManager(conf);
    network.setTimeFor(Height(0));
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto nodes = network.clients;
    auto node_1 = nodes[0];

    auto txs = genesisSpendable().map!(txb => txb.sign()).take(8).array;

    const b0 = nodes[0].getBlocksFrom(0, 1)[0];

    void checkHeight(Height height)
    {
        network.waitForPreimages(b0.header.enrollments, height);
        nodes[0].postTransaction(txs[height.value]);
        network.setTimeFor(height);
        network.assertSameBlocks(height);
    }

    // Check for adding blocks 1 to 4
    only(1, 2, 3, 4).each!(h => checkHeight(Height(h)));
}
