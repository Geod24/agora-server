/*******************************************************************************

    Tests restoring SCP Envelope state on restart

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.RestoreSCPState;

version (unittest):

import agora.common.ManagedDatabase;
import agora.consensus.protocol.Nominator;
import agora.test.Base;

/// A test to store SCP state and recover SCP state
unittest
{
    __gshared bool Checked = false;

    static class ReNominator : Nominator
    {
        /// Ctor
        mixin ForwardCtor!();

        ///
        override void restoreSCPState () @trusted
        {
            // on first boot the envelope store will be empty,
            // but on restart it should contain one or more envelopes
            // (note: the total count depends on SCP's internal state and can
            // change between SCP releases)
            if (Checked)
            {
                assert(this.store.length > 0);
                Checked = false;
            }
            super.restoreSCPState();
        }
    }

    static class ReValidator : TestValidatorNode
    {
        ///
        mixin ForwardCtor!();

        private static ManagedDatabase PersistentDB;

        protected override ManagedDatabase makeCacheDB ()
        {
            if (PersistentDB is null)
                PersistentDB = new ManagedDatabase(":memory:");
            return PersistentDB;
        }

        ///
        protected override ReNominator makeNominator (
            Parameters!(TestValidatorNode.makeNominator) args)
        {
            return new ReNominator(
                this.params, this.config.validator.key_pair, args,
                this.cacheDB, this.config.validator.nomination_interval,
                &this.acceptBlock);
        }
    }

    static class ReAPIManager : TestAPIManager
    {
        mixin ForwardCtor!();

        ///
        public override void createNewNode (Config conf, string file, int line)
        {
            if (this.nodes.length == 0)
            {
                assert(conf.validator.enabled);
                this.addNewNode!ReValidator(conf, file, line);
            }
            else
                super.createNewNode(conf, file, line);
        }
    }

    TestConf conf = TestConf.init;
    auto network = makeTestNetwork!ReAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto re_validator = network.clients[0];
    auto txes = genesisSpendable().map!(txb => txb.sign()).array();
    txes.each!(tx => re_validator.postTransaction(tx));
    network.expectHeightAndPreImg(Height(1), network.blocks[0].header);

    Checked = true;
    // Now shut down & restart one node
    network.restart(re_validator);
    network.waitForDiscovery();
    network.expectHeightAndPreImg(Height(1), network.blocks[0].header);
    assert(!Checked);
}
