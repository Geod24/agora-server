/*******************************************************************************

    Contains validation routines for pre-image

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.consensus.validation.PreImage;

import agora.consensus.data.Params;
import agora.consensus.data.PreImageInfo;
import agora.crypto.Hash;

version (unittest)
{
    import agora.consensus.data.Enrollment;
    import agora.crypto.ECC;

    import std.algorithm.mutation : reverse;
}

/*******************************************************************************

    Check the validity of a new pre-image information

    Pre-image infomation is considered valid if:
        - The keys for enrollment in two pieces of pre-image information are
            same
        - Height for a pre-image is greater than height for a current image
        - A current image is same as n times hashed value of a pre-image
            (n = difference of two heights).

    Params:
        newer = The pre-image information to check
        previous = The previous pre-image information

    Returns:
        `null` if the pre-image is valid, otherwise a string
        explaining the reason it is invalid.

*******************************************************************************/

public string isInvalidReason (in PreImageInfo newer,
    in PreImageInfo previous) nothrow @safe
{
    if (newer.utxo != previous.utxo)
        return "The pre-image's UTXO differs from its descendant";

    if (newer.height <= previous.height)
        return "The height of new pre-image is not greater than that of the previous one";

    Hash temp_hash = newer.hash;
    foreach (_; previous.height .. newer.height)
        temp_hash = hashFull(temp_hash);
    if (temp_hash != previous.hash)
        return "The pre-image has a invalid hash value";

    return null;
}

/// Ditto but returns `bool`, only usable in unittests
version (unittest)
public bool isValid (in PreImageInfo newer,
    in PreImageInfo previous) nothrow @safe
{
    return isInvalidReason(newer, previous) is null;
}

/// test for validity of pre-image
unittest
{
    auto params = new immutable(ConsensusParams)(2000);

    import agora.common.Types;

    Hash[] preimages;
    preimages ~= hashFull(Scalar.random());
    foreach (i; 0 .. params.ValidatorCycle)
        preimages ~= hashFull(preimages[i]);
    reverse(preimages);

    PreImageInfo prev_image = PreImageInfo(hashFull("abc"), preimages[0], Height(0));

    // valid pre-image
    PreImageInfo new_image = PreImageInfo(hashFull("abc"), preimages[100], Height(100));
    assert(new_image.isValid(prev_image));

    // invalid pre-image with wrong UTXO
    new_image = PreImageInfo(hashFull("xyz"), preimages[100], Height(100));
    assert(!new_image.isValid(prev_image));

    // invalid pre-image with wrong height number
    new_image = PreImageInfo(hashFull("abc"), preimages[1], Height(3));
    assert(!new_image.isValid(prev_image));

    // invalid pre-image with wrong hash value
    new_image = PreImageInfo(hashFull("abc"), preimages[101], Height(100));
    assert(!new_image.isValid(prev_image));
}
