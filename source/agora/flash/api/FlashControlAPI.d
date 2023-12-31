/*******************************************************************************

    Contains the user-facing API used to control the flash node,
    for example creating invoices and paying invoices.

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.flash.api.FlashControlAPI;

import agora.api.Handlers;
import agora.common.Amount;
import agora.common.Types;
import agora.crypto.ECC;
import agora.crypto.Key;
import agora.flash.api.FlashAPI;
import agora.flash.Config;
import agora.flash.Invoice;
import agora.flash.Route;
import agora.flash.Types;
import agora.consensus.data.UTXO;

import core.stdc.time;

/// Ditto
public interface FlashControlAPI : FlashAPI, BlockExternalizedHandler
{
@safe:
    /***************************************************************************

        Start the Flash node. This starts internal timers such as the
        periodic name registry timer.

    ***************************************************************************/

    public void start();

    /***************************************************************************

        Register the given secret key as being managed by the Flash node.

        Params:
            secret = the secret to register

    ***************************************************************************/

    public void registerKey (KeyPair secret);

    /***************************************************************************

        Get the list of managed channels.

        Params:
            keys = the keys to look up. If empty then all managed channels will
                be returned.

        Returns:
            the list of all managed channels by this Flash node for the
            given public keys (if any)

    ***************************************************************************/

    public ChannelConfig[] getManagedChannels (PublicKey[] keys);

    /***************************************************************************

        Get the list of managed channels.

        Params:
            chan_ids = the channel keys to look up. If empty then all managed
                channel info will be returned.

        Returns:
            the list of all managed channels by this Flash node for the
            given public keys (if any)

    ***************************************************************************/

    public ChannelInfo[] getChannelInfo (Hash[] chan_ids);

    /***************************************************************************

        Schedule opening a new channel with another flash node.
        If this funding_utxo is already used, an error is returned.
        Otherwise, the Listener will receive a notification through
        the onChannelNotify() API at a later point whenever the channel
        is accepted / rejected by the counter-party.

        Params:
            funding_utxo = the UTXO that will be used to fund the setup tx
            funding_utxo_hash = hash of `funding_utxo`
            capacity = the amount that will be used to fund the setup tx
            settle_time = closing settle time in number of blocks since last
                setup / update tx was published on the blockchain
            peer_pk = the public key of the counter-party flash node
            peer_address = network address of the peer to bootstrap the communication
                in case the peer is not registered in the name registry

        Returns:
            The channel ID, or an error if this funding UTXO is
            already used for another pending / open channel.

    ***************************************************************************/

    public Result!Hash openNewChannel (/* in */ UTXO funding_utxo,
        /* in */ Hash funding_utxo_hash, /* in */ Amount capacity,
        /* in */ uint settle_time, /* in */ Point peer_pk,
        /* in */ bool is_private, /* in */ Address peer_address);

    /***************************************************************************

        Begin a collaborative closure of a channel with the counter-party
        for the given channel ID.

        Params:
            reg_pk = the registered public key. If this key is not managed by
                this Flash node then an error will be returned.
            chan_id = the ID of the channel to close

        Returns:
            true if this channel ID exists and may be closed,
            else an error

    ***************************************************************************/

    public Result!bool beginCollaborativeClose (PublicKey reg_pk,
        /* in */ Hash chan_id);

    /***************************************************************************

        If the counter-party rejects a collaborative closure,
        the wallet may initiate a unilateral closure of the channel.

        This will publish the latest update transaction to the blockchain,
        and after the time lock expires the settlement transaction will be
        published too.

        Params:
            reg_pk = the registered public key. If this key is not managed by
                this Flash node then an error will be returned.
            chan_id = the ID of the channel to close

        Returns:
            true if this channel ID exists and may be closed,
            else an error

    ***************************************************************************/

    public Result!bool beginUnilateralClose (PublicKey reg_pk,
        /* in */ Hash chan_id);

    /***************************************************************************

        Create an invoice that can be paid by another party. A preimage is
        shared through a secure channel to the party which will pay the invoice.
        The hash of the preimage is used in the contract, which is then shared
        across zero or more channel hops. The invoice payer must reveal their
        preimage to prove.

        Params:
            reg_pk = the registered public key. If this key is not managed by
                this Flash node then an error will be returned.
            destination = the public key of the destination
            amount = the amount to invoice
            expiry = expiry time of this invoice
            description = optional description

        Returns:
            the invoice, or an error if this public key is not recognized

    ***************************************************************************/

    public Result!Invoice createNewInvoice (PublicKey reg_pk, /* in */ Amount amount,
        /* in */ time_t expiry, /* in */ string description = null);

    /***************************************************************************

        Attempt to find a payment path for the invoice and pay for the
        invoice.

        If a payment path cannot be found, or if the payment fails along
        the payment path then the listener will be notified through the
        `onPaymentFailure` endpoint.

        If the payment succeeds the `onPaymentSuccess` endpoint will be
        called on the listener.

        Params:
            reg_pk = the registered public key. If this key is not managed by
                this Flash node then an error will be returned.
            invoice = the invoice to pay

    ***************************************************************************/

    public void payInvoice (PublicKey reg_pk, /* in */ Invoice invoice);
}
