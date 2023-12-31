/*******************************************************************************

    Test whether genesis block has enrollment data and
    existing Genesis Transactions

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.GenesisBlock;

version (unittest):

import agora.test.Base;

/// ditto
unittest
{
    auto network = makeTestNetwork!TestAPIManager(TestConf.init);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto nodes = network.clients;
    auto node_1 = nodes[0];

    nodes.all!(node => node.getBlocksFrom(0, 1)[0] == network.blocks[0])
        .retryFor(2.seconds);

    auto txes = genesisSpendable().map!(txb => txb.sign()).array();
    txes.each!(tx => node_1.postTransaction(tx));
    network.expectHeightAndPreImg(Height(1), network.blocks[0].header);
}
