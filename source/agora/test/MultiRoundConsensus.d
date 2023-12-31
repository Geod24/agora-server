/*******************************************************************************

    Tests for reaching consensus in multiple rounds instead of 1 round.
    In this test, we make nodes reject nominations for several rounds
    deliberately until one is accepted at a round R, where R could be arbitrarily
    high.

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.MultiRoundConsensus;

version (unittest):

import agora.consensus.protocol.Nominator;
import agora.test.Base;

import core.stdc.inttypes;
import core.thread;

import scpd.types.Stellar_types;
import scpd.types.Stellar_SCP;

/// ditto
unittest
{
    extern (C++) static class CustomNominator : Nominator
    {
        // To see how many voting rounds are needed to reach consensus
        public __gshared int round_number;

    extern (D):

        mixin ForwardCtor!();

    extern (C++):

        ///
        public override uint64_t computeHashNode (uint64_t slot_idx,
            ref const(Value) prev, bool is_priority, int32_t round_num,
            ref const(NodeID) node_id) nothrow
        {
            this.round_number = round_num;
            return super.computeHashNode(slot_idx, prev, is_priority,
                round_num, node_id);
        }
    }

    static class CustomValidator : TestValidatorNode
    {
        mixin ForwardCtor!();

        ///
        protected override CustomNominator makeNominator (
            Parameters!(TestValidatorNode.makeNominator) args)
        {
            return new CustomNominator(
                this.params, this.config.validator.key_pair, args,
                this.cacheDB, this.config.validator.nomination_interval,
                &this.acceptBlock);
        }
    }

    static class CustomAPIManager : TestAPIManager
    {
        mixin ForwardCtor!();

        /// set base class
        public override void createNewNode (Config conf, string file, int line)
        {
            if (this.nodes.length == 0)
                this.addNewNode!CustomValidator(conf, file, line);
            else
                super.createNewNode(conf, file, line);
        }
    }

    TestConf conf;
    conf.consensus.quorum_threshold = 100;
    conf.node.timeout = 5.seconds;

    auto network = makeTestNetwork!CustomAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();
    auto nodes = network.clients;
    auto validator = network.clients[0];

    // Make one of six validators stop responding for a while
    nodes.drop(1).take(1).each!(node => node.ctrl.sleep(conf.node.timeout, true));

    // Block 1 with multiple consensus rounds
    auto txs = genesisSpendable().map!(txb => txb.sign()).array();
    txs.each!(tx => validator.postTransaction(tx));

    network.expectHeightAndPreImg(Height(1), network.blocks[0].header, conf.node.timeout + 5.seconds);
    assert(CustomNominator.round_number >= 2,
        format("The validator's round number is %s. Expected: above %s",
            CustomNominator.round_number, 2));
}
