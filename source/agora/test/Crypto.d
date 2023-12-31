/*******************************************************************************

    Contains extra tests for the `crypto` library

    Those tests do not belong to the crypto library, but ensures that it
    integrates correctly with utilities we use.

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module agora.test.Crypto;

import agora.crypto.ECC;
import agora.crypto.Schnorr;
import agora.crypto.Types;
import agora.serialization.Serializer;

unittest
{
    auto s = Scalar("0x0e00a8df701806cb4deac9bb09cc85b097ee713e055b9d2bf1daf668b3f63778");

    // Test default formatting behavior with Ocean's sformat/log
    // The library test integration with Phobos
    import dtext.format.Formatter : format;
    assert(format("{}", s) == "**SCALAR**");

    import vibe.data.json;
    assert(s.serializeToJsonString() == "\"**SCALAR**\"",
           s.serializeToJsonString());
}

// Test serialization for types in `agora.crypto.ECC`
unittest
{
    testSymmetry!Scalar();
    testSymmetry(Scalar.random());
    testSymmetry!Point();
    testSymmetry(Scalar.random().toPoint());
    // Make sure it's serialized as a value type (without length)
    assert(Scalar.random().toPoint().serializeFull().length == Point.sizeof);
}

// Test serialization for types in `agora.crypto.Schnorr`
unittest
{
    const KP = Pair.random();
    auto signature = Signature(KP.V, KP.v);
    auto bytes = signature.serializeFull();
    assert(bytes.deserializeFull!Signature == signature);
}
