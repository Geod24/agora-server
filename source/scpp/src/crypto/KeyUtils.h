#pragma once

// Copyright 2016 Stellar Development Foundation and contributors. Licensed
// under the Apache License, Version 2.0. See the COPYING file at the root
// of this distribution or at http://www.apache.org/licenses/LICENSE-2.0

#include "crypto/StrKey.h"
#include "util/SecretValue.h"
#include "xdr/Stellar-types.h"

#include <sodium.h>

#include <string>

namespace stellar
{

class SecretKey;

template <typename T> struct KeyFunctions
{
    struct getKeyTypeEnum
    {
    };

    static std::string getKeyTypeName();
    static bool getKeyVersionIsSupported(strKey::StrKeyVersionByte keyVersion);
    static typename getKeyTypeEnum::type
    toKeyType(strKey::StrKeyVersionByte keyVersion);
    static strKey::StrKeyVersionByte
    toKeyVersion(typename getKeyTypeEnum::type keyType);
    static uint256& getKeyValue(T& key);
    static uint256 const& getKeyValue(T const& key);
};

// signer key utility functions
namespace KeyUtils
{

template <typename T>
typename std::enable_if<!std::is_same<T, SecretKey>::value, std::string>::type
toStrKey(T const& key)
{
    return strKey::toStrKey(KeyFunctions<T>::toKeyVersion(0),
                            KeyFunctions<T>::getKeyValue(key))
        .value;
}

template <typename T>
typename std::enable_if<std::is_same<T, SecretKey>::value, SecretValue>::type
toStrKey(T const& key)
{
    return strKey::toStrKey(KeyFunctions<T>::toKeyVersion(0),
                            KeyFunctions<T>::getKeyValue(key));
}

template <typename T>
typename std::enable_if<!std::is_same<T, SecretKey>::value, std::string>::type
toShortString(T const& key)
{
    return toStrKey(key).substr(0, 5);
}

template <typename T>
typename std::enable_if<std::is_same<T, SecretKey>::value, SecretValue>::type
toShortString(T const& key)
{
    return SecretValue{toStrKey(key).value.substr(0, 5)};
}

std::size_t getKeyVersionSize(strKey::StrKeyVersionByte keyVersion);

template <typename T, typename F>
bool
canConvert(F const& fromKey)
{
    return KeyFunctions<T>::getKeyVersionIsSupported(
        KeyFunctions<F>::toKeyVersion(fromKey.type()));
}

template <typename T, typename F>
T
convertKey(F const& fromKey)
{
    T toKey;
    toKey.type(KeyFunctions<T>::toKeyType(
        KeyFunctions<F>::toKeyVersion(fromKey.type())));
    KeyFunctions<T>::getKeyValue(toKey) = KeyFunctions<F>::getKeyValue(fromKey);
    return toKey;
}
}
}
