/*******************************************************************************

    Contains in-memory representation of Lightning Network topology

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.flash.Network;

import agora.flash.api.FlashAPI;
import agora.flash.Config;
import agora.flash.Channel;
import agora.flash.Route;
import agora.flash.Types;

import agora.common.Set;
import agora.common.Amount;
import agora.crypto.ECC;
import agora.crypto.Hash;

///
private struct NetworkNode
{
    /// Channels that this NetworkNode is a part of
    private Set!Hash[Point] channels;
}

///
public class Network
{
    /// Nodes
    private NetworkNode[Point] nodes;

    ///
    private static struct ChannelRoutingInfo
    {
        /// Public key of the funder of the channel.
        public Point funder_pk;

        /// The total amount funded in this channel. This information is
        /// derived from the Outputs of the funding transaction.
        public Amount capacity;

        /// If this channel can be used as an intermediate hop
        public bool is_private;
    }

    /// Static information about channel that are useful for routing
    private ChannelRoutingInfo[Hash] routing_info;

    /// Delegate to lookup Channels by their ID
    private ChannelUpdate delegate (Hash chan_id, Point from) @safe nothrow lookupUpdate;

    /// Ctor
    public this (ChannelUpdate delegate (Hash chan_id, Point from) @safe nothrow lookupUpdate)
    {
        this.lookupUpdate = lookupUpdate;
    }

    version (unittest) public this () { }

    /***************************************************************************

        Add a Channel to the network

        Params:
            chan_conf = ChannelConfig of the Channel to be added

    ***************************************************************************/

    public void addChannel (in ChannelConfig chan_conf) @safe nothrow
    {
        const funder_pk = chan_conf.funder_pk;
        const peer_pk = chan_conf.peer_pk;

        this.routing_info[chan_conf.chan_id] = ChannelRoutingInfo(
            chan_conf.funder_pk, chan_conf.capacity, chan_conf.is_private);

        this.addChannel(funder_pk, peer_pk, chan_conf);
        this.addChannel(peer_pk, funder_pk, chan_conf);
    }

    ///
    private void addChannel (Point peer1_pk, Point peer2_pk,
        in ChannelConfig chan_conf) @safe nothrow
    {
        const chan_id = chan_conf.chan_id;

        if (peer1_pk !in this.nodes)
            this.nodes[peer1_pk] = NetworkNode.init;

        if (auto chns = peer2_pk in this.nodes[peer1_pk].channels)
            chns.put(chan_id);
        else
            this.nodes[peer1_pk].channels[peer2_pk] = Set!Hash.from([chan_id]);
    }

    /***************************************************************************

        Remove a Channel from the network

        Params:
            chan_conf = ChannelConfig of the Channel to be removed

    ***************************************************************************/

    public void removeChannel (in ChannelConfig chan_conf) @safe nothrow
    {
        const funder_pk = chan_conf.funder_pk;
        const peer_pk = chan_conf.peer_pk;

        this.routing_info.remove(chan_conf.chan_id);

        this.removeChannel(funder_pk, peer_pk, chan_conf);
        this.removeChannel(peer_pk, funder_pk, chan_conf);
    }

    ///
    private void removeChannel (Point peer1_pk, Point peer2_pk,
        in ChannelConfig chan_conf) @safe nothrow
    {
        const chan_id = chan_conf.chan_id;

        // Remove channels
        this.nodes[peer1_pk].channels[peer2_pk].remove(chan_id);

        // If no channels remain, remove the peer
        if (this.nodes[peer1_pk].channels[peer2_pk].length == 0)
            this.nodes[peer1_pk].channels.remove(peer2_pk);

        // If no peers remain, remove the node
        if (this.nodes[peer1_pk].channels.length == 0)
            this.nodes.remove(peer1_pk);
    }

    /***************************************************************************

        Build a path between two nodes in the network

        Params:
            from_pk = Source node public key
            to_pk = Destination node public key
            amount = Amount of the payment
            ignore_chans = Channels to ignore

        Returns:
            If found, path from source to destination

    ***************************************************************************/

    public Hop[] getPaymentPath (Point from_pk, Point to_pk, Amount amount,
        Set!Hash ignore_chans = Set!Hash.init) @safe nothrow
    {
        import std.typecons;
        import std.algorithm.mutation : reverse;

        // Unknown nodes
        if (from_pk !in this.nodes || to_pk !in this.nodes)
            return null;

        Amount[Point] fees;
        Hop[Point] prev;
        Set!Point unvisited;

        foreach (pk; this.nodes.byKey())
        {
            fees[pk] = pk == from_pk ? Amount(0) : Amount.MaxUnitSupply;
            unvisited.put(pk);
        }

        while (unvisited.length > 0)
        {
            import std.algorithm;
            import std.array;

            // Pick the node with the smallest fee
            Point min_pk = unvisited[].map!(node => tuple(node, fees[node]))
                .minElement!"a[1]"[0];

            // Rest of the nodes are unreachable, terminate
            if (fees[min_pk] == Amount.MaxUnitSupply)
                break;

            auto min_node = this.nodes[min_pk];

            foreach (peer_pk; min_node.channels.byKey())
                if (peer_pk in unvisited)
                {
                    auto channel_filter = (Hash chan_id) {
                        if (chan_id in ignore_chans)
                            return false;
                        auto info = this.routing_info[chan_id];
                        if (amount > info.capacity ||
                            (info.is_private && info.funder_pk != to_pk && info.funder_pk != from_pk))
                            return false;
                        return true;
                    };

                    auto chans = min_node.channels[peer_pk][]
                        .filter!(chan => channel_filter(chan));
                    auto updates = chans.map!(chan => this.lookupUpdate(chan, min_pk))
                        .filter!(update => update != ChannelUpdate.init);
                    auto hop_fees = updates.map!(update => tuple(update.chan_id, update.getTotalFee(amount)))
                        .filter!(tup => tup[1].isValid()).array;

                    if (hop_fees.length == 0)
                        continue;

                    auto min_fee_hop = hop_fees.minElement!"a[1]";
                    auto chan = min_fee_hop[0];
                    auto chan_fee = min_fee_hop[1];

                    auto total_fee = fees[min_pk];
                    if (!total_fee.add(chan_fee))
                        assert(0);
                    if (total_fee < fees[peer_pk])
                    {
                        fees[peer_pk] = total_fee;
                        prev[peer_pk] = Hop(min_pk, chan, chan_fee);
                    }
                }

            unvisited.remove(min_pk);
            if (min_pk == to_pk)
                break;
        }
        // No path found
        if (to_pk !in prev)
            return null;

        Hop[] path;
        Amount hop_fee;
        // Trace the path from destination to source
        do
        {
            auto hop = prev[to_pk];
            auto update = this.lookupUpdate(hop.chan_id, hop.pub_key);
            path ~= Hop(to_pk, hop.chan_id, hop_fee, update.htlc_delta);
            to_pk = hop.pub_key;
            hop_fee = hop.fee;
        } while(to_pk != from_pk);

        return path.reverse();
    }

    unittest
    {
        auto ln = new Network();
        ChannelConfig conf;
        conf.funder_pk = Scalar.random().toPoint();
        conf.peer_pk = Scalar.random().toPoint();
        conf.chan_id = hashFull(1);
        ln.addChannel(conf);

        conf.funder_pk = conf.peer_pk;
        conf.peer_pk = Scalar.random().toPoint();
        conf.chan_id = hashFull(2);
        ln.addChannel(conf);

        assert(ln.nodes.length == 3);
        ln.removeChannel(conf);
        assert(ln.nodes.length == 2);
        assert(conf.peer_pk !in ln.nodes);
    }
}

///
unittest
{
    import std.range;
    import std.algorithm;

    auto ln = new Network((Hash chan_id, Point) {
        return ChannelUpdate(chan_id, PaymentDirection.TowardsPeer, Amount(1), Amount(0));
    });
    Point[] pks;
    iota(5).each!(idx => pks ~= Scalar.random().toPoint());

    ChannelConfig conf;
    conf.capacity = 1.coins;
    conf.funder_pk = pks[0];
    conf.peer_pk = pks[1];
    conf.chan_id = hashFull(1);
    ln.addChannel(conf);
    // #0 -- #1

    conf.funder_pk = pks[0];
    conf.peer_pk = pks[2];
    conf.chan_id = hashFull(2);
    ln.addChannel(conf);
    // #0 -- #1
    //    \__ #2

    auto path = ln.getPaymentPath(pks[0], pks[1], Amount(1));
    assert(path.length == 1);
    assert(path[0].pub_key == pks[1]);
    assert(path[0].chan_id == hashFull(1));

    path = ln.getPaymentPath(pks[0], pks[2], Amount(1));
    assert(path.length == 1);
    assert(path[0].pub_key == pks[2]);
    assert(path[0].chan_id == hashFull(2));

    path = ln.getPaymentPath(pks[1], pks[2], Amount(1));
    assert(path.length == 2);
    assert(path[0].pub_key == pks[0]);
    assert(path[0].chan_id == hashFull(1));
    assert(path[1].pub_key == pks[2]);
    assert(path[1].chan_id == hashFull(2));

    conf.funder_pk = pks[3];
    conf.peer_pk = pks[4];
    conf.chan_id = hashFull(3);
    ln.addChannel(conf);
    // #0 -- #1
    //    \__ #2    #3 -- #4

    foreach (node1; 0 .. 3)
        foreach (node2; 3 .. 5)
            assert(ln.getPaymentPath(pks[node1], pks[node2], Amount(1)) == null);

    path = ln.getPaymentPath(pks[3], pks[4], Amount(1));
    assert(path.length == 1);
    assert(path[0].pub_key == pks[4]);
    assert(path[0].chan_id == hashFull(3));

    conf.funder_pk = pks[1];
    conf.peer_pk = pks[2];
    conf.chan_id = hashFull(4);
    ln.addChannel(conf);
    // #0 -- #1
    //   \    |
    //    \__ #2    #3 -- #4

    path = ln.getPaymentPath(pks[1], pks[2], Amount(1));
    assert(path.length == 1);
    assert(path[0].pub_key == pks[2]);
    assert(path[0].chan_id == hashFull(4));

    // Ignore the direct channel between #0 and #2
    path = ln.getPaymentPath(pks[0], pks[2], Amount(1), Set!Hash.from([hashFull(2)]));
    assert(path.length == 2);
    assert(path[0].pub_key == pks[1]);
    assert(path[0].chan_id == hashFull(1));
    assert(path[1].pub_key == pks[2]);
    assert(path[1].chan_id == hashFull(4));

    // Can't route 2.coins
    path = ln.getPaymentPath(pks[0], pks[2], 2.coins);
    assert(path == null);

    // unknown keys
    path = ln.getPaymentPath(Scalar.random().toPoint(), pks[1], Amount(1));
    assert(path is null);

    conf.funder_pk = pks[2];
    conf.peer_pk = pks[3];
    conf.chan_id = hashFull(5);
    conf.is_private = true;
    ln.addChannel(conf);
    // #0 -- #1
    //   \    |
    //    \__ #2 -p- #3 -- #4

    // anything that should use private channel as a hop should fail
    foreach (node1; 0 .. 2)
        assert(ln.getPaymentPath(pks[node1], pks[4], Amount(1)) == null);
    foreach (node2; 0 .. 2)
        assert(ln.getPaymentPath(pks[4], pks[node2], Amount(1)) == null);

    // should be able to route directly between #2 and #3
    path = ln.getPaymentPath(pks[2], pks[3], Amount(1));
    assert(path.length == 1);
    assert(path[0].pub_key == pks[3]);
    assert(path[0].chan_id == hashFull(5));

    path = ln.getPaymentPath(pks[3], pks[2], Amount(1));
    assert(path.length == 1);
    assert(path[0].pub_key == pks[2]);
    assert(path[0].chan_id == hashFull(5));

    // should not be able to route from left part of the graph to #3
    foreach (node1; 0 .. 2)
        assert(ln.getPaymentPath(pks[node1], pks[3], Amount(1)) == null);

    // should be able to route from right part of the graph to #2
    path = ln.getPaymentPath(pks[4], pks[2], Amount(1));
    assert(path[$-1].pub_key == pks[2]);
    assert(path[$-1].chan_id == hashFull(5));
}
