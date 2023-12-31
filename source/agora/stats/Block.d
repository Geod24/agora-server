/*******************************************************************************

    Stats corresponding to blocks

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.stats.Block;

import agora.stats.Stats;

///
public struct BlockStats
{
    public ulong agora_block_height_counter;
    public ulong agora_block_externalized_total;
    public ulong agora_block_enrollments_gauge;
    public ulong agora_block_txs_total;
    public ulong agora_block_txs_amount_total;
}
