/*******************************************************************************

    Contains tests for the Block creation and adding blocks to the ledger,
    as well as the catch-up

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.Ledger;

version (unittest):

import agora.consensus.data.UTXO;
import agora.consensus.Fee;
import agora.consensus.validation;
import agora.crypto.Hash;
import agora.script.Engine;
import agora.script.Lock;
import agora.script.Signature;
import agora.serialization.Serializer;
import agora.test.Base;

import core.thread;

///
unittest
{
    TestConf conf = TestConf.init;
    auto network = makeTestNetwork!TestAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto nodes = network.clients;
    auto node_1 = nodes[0];

    Transaction[][] block_txes; /// per-block array of transactions (genesis not included)

    // Get the genesis block, make sure it's the only block externalized
    auto blocks = node_1.getBlocksFrom(0, 2);
    assert(blocks.length == 1);

    foreach (block_idx; 0 .. 10)  // create 10 blocks
    {
        // create enough tx's for a single block
        Transaction[] txs = blocks[block_idx].spendable().map!(txb => txb.sign()).array;

        // send each tx to one node
        txs.each!(tx => network.postAndEnsureTxInPool(tx));

        // now create the next block
        network.expectHeightAndPreImg(Height(block_idx + 1), blocks[0].header);

        blocks ~= node_1.getBlocksFrom(block_idx + 1, 2);
        assert(blocks.length == block_idx + 2);
        block_txes ~= txs.sort.array;
    }

    assert(blocks[0] == network.blocks[0]);

    // exclude genesis block
    assert(blocks[1 .. $].enumerate.each!((idx, block) =>
        assert(block.txs == block_txes[idx])
    ));

    blocks = node_1.getBlocksFrom(0, 1);
    assert(blocks.length == 1 && blocks[0] == network.blocks[0]);

    blocks = node_1.getBlocksFrom(10, 1);
    assert(blocks.length == 1 && blocks[0].txs == block_txes[9]);  // -1 as genesis block not included

    // over the limit => return up to the highest block
    assert(node_1.getBlocksFrom(0, 100).length == 11);

    // higher index than available => return nothing
    assert(node_1.getBlocksFrom(100, 10).length == 0);
}

/// test catch-up phase after initial booting (periodic catch-up)
unittest
{
    TestConf conf = { full_nodes : 3 };
    auto network = makeTestNetwork!TestAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    // node_1 is one of the validators
    auto nodes = network.clients;
    auto node_1 = nodes[0];

    // ignore transaction propagation and periodically retrieve blocks via getBlocksFrom
    nodes[GenesisValidators .. $].each!(node => node.filter!(node.postTransaction));

    auto txs = genesisSpendable().map!(txb => txb.sign()).array();
    txs.each!(tx => node_1.postTransaction(tx));
    network.expectHeightAndPreImg(Height(1), network.blocks[0].header);

    txs = txs.map!(tx => TxBuilder(tx).sign()).array();
    txs.each!(tx => node_1.postTransaction(tx));
    network.expectHeightAndPreImg(Height(2), network.blocks[0].header);
}

/// Merkle Proof
unittest
{
    TestConf conf = TestConf.init;
    auto network = makeTestNetwork!TestAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto nodes = network.clients;
    auto node_1 = nodes[0];

    auto gen_key_pair = WK.Keys.Genesis;
    auto txs = genesisSpendable().map!(txb => txb.sign()).array();
    txs.each!(tx => node_1.postTransaction(tx));

    Hash[] hashes;
    hashes.reserve(txs.length);
    foreach (ref e; txs)
        hashes ~= hashFull(e);

    // transactions are ordered lexicographically by hash in the Merkle tree
    hashes.sort!("a < b");

    const Hash hab = hashMulti(hashes[0], hashes[1]);
    const Hash hcd = hashMulti(hashes[2], hashes[3]);
    const Hash hef = hashMulti(hashes[4], hashes[5]);
    const Hash hgh = hashMulti(hashes[6], hashes[7]);

    const Hash habcd = hashMulti(hab, hcd);
    const Hash hefgh = hashMulti(hef, hgh);

    const Hash expected_root = hashMulti(habcd, hefgh);

    // wait for transaction propagation
    network.expectHeightAndPreImg(Height(1), network.blocks[0].header);

    Hash[] merkle_path;
    foreach (node; nodes)
    {
        merkle_path = node.getMerklePath(1, hashes[2]);
        assert(merkle_path.length == 3);
        assert(merkle_path[0] == hashes[3]);
        assert(merkle_path[1] == hab);
        assert(merkle_path[2] == hefgh);
        assert(expected_root == Block.checkMerklePath(hashes[2], merkle_path, 2));
        assert(expected_root != Block.checkMerklePath(hashes[3], merkle_path, 2));

        merkle_path = node.getMerklePath(1, hashes[4]);
        assert(merkle_path.length == 3);
        assert(merkle_path[0] == hashes[5]);
        assert(merkle_path[1] == hgh);
        assert(merkle_path[2] == habcd);
        assert(expected_root == Block.checkMerklePath(hashes[4], merkle_path, 4));
        assert(expected_root != Block.checkMerklePath(hashes[5], merkle_path, 4));

        merkle_path = node.getMerklePath(1, Hash.init);
        assert(merkle_path.length == 0);
    }
}

/// test behavior of receiving double-spend transactions
unittest
{
    TestConf conf = TestConf.init;
    auto network = makeTestNetwork!TestAPIManager(conf);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    auto nodes = network.clients;
    auto node_1 = nodes[0];

    auto txs = network.blocks[0].spendable.map!(txb => txb.sign()).array();
    txs.each!(tx => network.postAndEnsureTxInPool(tx));

    network.expectHeightAndPreImg(Height(1), network.blocks[0].header);

    txs = txs.map!(tx => TxBuilder(tx).sign()).array();
    txs.each!(tx => network.postAndEnsureTxInPool(tx));
    network.expectHeightAndPreImg(Height(2), network.blocks[0].header);

    txs = txs.map!(tx => TxBuilder(tx).sign()).array();

    // create a deep-copy of the first tx
    auto backup_tx = deserializeFull!Transaction(serializeFull(txs[0]));

    // create a double-spend tx
    txs[0].inputs[0] = txs[1].inputs[0];
    txs[0].outputs[0].value = txs[1].outputs[0].value - Amount(1);
    auto signature = WK.Keys.Genesis.sign(txs[0].getChallenge());
    txs[0].inputs[0].unlock = genKeyUnlock(signature);

    scope payload_checker = new FeeManager();
    scope checker = &payload_checker.check;

    // make sure the transaction is still authentic (signature is correct),
    // even if it's double spending
    const genesis_block = node_1.getBlocksFrom(0, 1)[0];
    auto reason = txs[0].isInvalidReason(new Engine(16_384, 512),
        (in Hash, out UTXO value)
        {
            value = UTXO(0, txs[0].outputs[0]);
            return true;
        }, Height(0),
        checker, hash => 0.coins);
    assert(reason is null, reason);
    txs.each!(tx => node_1.postTransaction(tx));

    network.expectHeight(Height(2));  // no new block yet (1 rejected tx)

    network.postAndEnsureTxInPool(backup_tx);
    network.expectHeightAndPreImg(Height(3), network.blocks[0].header);  // new block finally created
}

// Ensure that when creating a frozen UTXO, the refund is not frozen too
// See https://github.com/bosagora/agora/issues/1440
unittest
{
    auto network = makeTestNetwork!TestAPIManager(TestConf.init);
    network.start();
    scope(exit) network.shutdown();
    scope(failure) network.printLogs();
    network.waitForDiscovery();

    // Create a freezing tx with two outputs:
    // 1) A refund of 1k
    // 2) A very large frozen amount (60.999k)
    Amount freezeAmount = network.blocks[0].frozens.front.outputs[0].value;
    // Must be under Amount.MinFreezeAmount so that the refund isn't frozen
    freezeAmount -= 1_000.coins;
    auto tx = network.blocks[0].spendable
        .map!(txb => txb
              .draw(freezeAmount, WK.Keys.AA.address.only).sign(OutputType.Freeze)
        ).front;

    assert(tx.outputs.length == 2);
    network.clients[0].postTransaction(tx);

    // Wait for the block to be created
    network.expectHeightAndPreImg(Height(1), network.blocks[0].header);
    const b1 = network.clients[0].getBlock(1);
    assert(b1.txs.length == 1);

    // Now spend the refund transaction (output index is 0 as it is sorted and lock is same value but ammount is less)
    auto tx2 = TxBuilder(b1.txs[0], 0).sign();
    assert(tx2.outputs.length == 1);

    network.postAndEnsureTxInPool(tx2); // Make sure it makes it into the block
    network.expectHeightAndPreImg(Height(2), network.blocks[0].header);
    assert(network.clients[0].getBlock(2).txs.length == 1);
}
