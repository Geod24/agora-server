/*******************************************************************************

    C++-side utilities for D code, such as wrapper for vector.push_back

    Copyright:
        Copyright (c) 2019-2021 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module scpd.types.Utils;

import scpd.Cpp;
import scpd.types.Stellar_SCP;
import scpd.types.Stellar_types;
import scpd.types.XDRBase;

extern(C++) public shared_ptr!SCPQuorumSet makeSharedSCPQuorumSet (
    ref const(SCPQuorumSet)) nothrow @nogc @safe;


/// Utility function for SCP
public inout(opaque_vec!()) toVec (scope ref inout(Hash) data) nothrow @nogc
{
    return (cast(inout(ubyte[]))data[]).toVec();
}

/// Ditto
public inout(opaque_vec!()) toVec (scope inout ubyte[] data) nothrow @nogc
{
    inout opaque_vec!() ret;
    ret.reserve(data.length);
    foreach (elem; data)
        ret.base.push_back(cast(ubyte) elem);
    return ret;
}

public SCPQuorumSet dup (ref const(SCPQuorumSet) orig)
{
    SCPQuorumSet ret;
    ret.threshold = orig.threshold;
    foreach (entry; orig.validators.constIterator)
        push_back(ret.validators, entry);
    assert(orig.innerSets.length == 0);
    return ret;
}

// This triggers a DMD bug :(
//extern(C++, `stellar`):
extern(C++):

public void push_back(T, VectorT) (ref VectorT this_, ref T value) @safe pure nothrow @nogc;
// Workarounds for Dlang issue #20805
public void push_back_vec (void*, const(void)*) @safe pure nothrow @nogc;
public Value duplicate_value (const(void)*) @safe pure nothrow @nogc;
