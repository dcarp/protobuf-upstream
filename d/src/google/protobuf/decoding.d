module google.protobuf.decoding;

import std.algorithm : map;
import std.exception : enforce;
import std.range : ElementType, empty, isInputRange;
import std.traits : isArray, isAssociativeArray, isBoolean, isFloatingPoint, isIntegral, KeyType, ValueType;
import google.protobuf.common;
import google.protobuf.internal;

T fromProtobuf(T, R)(ref R inputRange)
if (isInputRange!R && isBoolean!T)
{
    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");

    return cast(T) fromVarint(inputRange);
}

unittest
{
    import std.array : array;
    import google.protobuf.encoding : toProtobuf;

    auto buffer = true.toProtobuf.array;
    assert(buffer.fromProtobuf!bool);
}

T fromProtobuf(T, Wire wire = Wire.none, R)(ref R inputRange)
if (isInputRange!R && isIntegral!T)
{
    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");

    static if (wire == Wire.none)
    {
        return cast(T) fromVarint(inputRange);
    }
    else static if (wire == Wire.fixed)
    {
        return inputRange.decodeFixed!T;
    }
    else static if (wire == Wire.zigzag)
    {
        return cast(T) zagZig(fromVarint(inputRange));
    }
    else
    {
        assert(0, "Invalid wire encoding");
    }
}

unittest
{
    import std.array : array;
    import google.protobuf.encoding : toProtobuf;

    auto buffer = 10.toProtobuf.array;
    assert(buffer.fromProtobuf!int == 10);
    buffer = (-1).toProtobuf.array;
    assert(buffer.fromProtobuf!int == -1);
    buffer = (-1L).toProtobuf.array;
    assert(buffer.fromProtobuf!long == -1L);
    buffer = 0xffffffffffffffffUL.toProtobuf.array;
    assert(buffer.fromProtobuf!long == 0xffffffffffffffffUL);

    buffer = 1.toProtobuf!(Wire.fixed).array;
    assert(buffer.fromProtobuf!(int, Wire.fixed) == 1);
    buffer = (-1).toProtobuf!(Wire.fixed).array;
    assert(buffer.fromProtobuf!(int, Wire.fixed) == -1);
    buffer = 0xffffffffU.toProtobuf!(Wire.fixed).array;
    assert(buffer.fromProtobuf!(uint, Wire.fixed) == 0xffffffffU);
    buffer = 1L.toProtobuf!(Wire.fixed).array;
    assert(buffer.fromProtobuf!(long, Wire.fixed) == 1L);

    buffer = 1.toProtobuf!(Wire.zigzag).array;
    assert(buffer.fromProtobuf!(int, Wire.zigzag) == 1);
    buffer = (-1).toProtobuf!(Wire.zigzag).array;
    assert(buffer.fromProtobuf!(int, Wire.zigzag) == -1);
    buffer = 1L.toProtobuf!(Wire.zigzag).array;
    assert(buffer.fromProtobuf!(long, Wire.zigzag) == 1L);
    buffer = (-1L).toProtobuf!(Wire.zigzag).array;
    assert(buffer.fromProtobuf!(long, Wire.zigzag) == -1L);
}

T fromProtobuf(T, R)(ref R inputRange)
if (isInputRange!R && isFloatingPoint!T)
{
    return inputRange.decodeFixed!T;
}

unittest
{
    import std.array : array;
    import google.protobuf.encoding : toProtobuf;

    auto buffer = (0.0).toProtobuf.array;
    assert(buffer.fromProtobuf!double == 0.0);
    buffer = (0.0f).toProtobuf.array;
    assert(buffer.fromProtobuf!float == 0.0f);
}

T fromProtobuf(T, R)(ref R inputRange)
if (isInputRange!R && (is(T == string) || is(T == bytes)))
{
    import std.array : array;

    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");

    R fieldRange = inputRange.takeLengthPrefixed;

    return cast(T) fieldRange.array;
}

unittest
{
    import std.array : array;
    import google.protobuf.encoding : toProtobuf;

    auto buffer = "abc".toProtobuf.array;
    assert(buffer.fromProtobuf!string == "abc");
    buffer = "".toProtobuf.array;
    assert(buffer.fromProtobuf!string.empty);
    buffer = (cast(bytes) [1, 2, 3]).toProtobuf.array;
    assert(buffer.fromProtobuf!bytes == (cast(bytes) [1, 2, 3]));
    buffer = (cast(bytes) []).toProtobuf.array;
    assert(buffer.fromProtobuf!bytes.empty);
}

T fromProtobuf(T, Wire wire = Wire.none, R)(ref R inputRange)
if (isInputRange!R && isArray!T && !is(T == string) && !is(T == bytes))
{
    import std.array : Appender;

    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");

    R fieldRange = inputRange.takeLengthPrefixed;

    Appender!T result;
    static if (wire = Wire.none)
    {
        while (!fieldRange.empty)
            result ~= fieldRange.fromProtobuf!(ElementType!T);
    }
    else
    {
        static assert(isIntegral!(ElementType!T), "Cannot specify wire format for non-integral arrays");

        while (!fieldRange.empty)
            result ~= fieldRange.fromProtobuf!(ElementType!T, wire);
    }

    return result.data;
}

T fromProtobuf(T, R)(ref R inputRange, T result = defaultValue!T)
if (isInputRange!R && (is(T == class) || is(T == struct)))
{
    import std.traits : hasMember;

    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");

    static if (is(T == class))
    {
        if (result is null)
            result = new T;
    }

    static if (hasMember!(T, "fromProtobuf"))
    {
        return result.fromProtobuf(inputRange);
    }
    else
    {
        while (!inputRange.empty)
        {

            auto tagWire = inputRange.decodeTag;

            chooseFieldDecoder:
            switch (tagWire.tag)
            {
            foreach (fieldName; Message!T.fieldNames)
            {
                case protoByField!(mixin("T." ~ fieldName)).tag:
                {
                    enum proto = protoByField!(mixin("T." ~ fieldName));
                    enum wireTypeExpected = wireType!(proto, typeof(mixin("T." ~ fieldName)));

                    enforce!ProtobufException(tagWire.wireType == wireTypeExpected, "Wrong wire format");
                    inputRange.fromProtobufByField!(mixin("T." ~ fieldName))(result);
                    break chooseFieldDecoder;
                }
            }
            default:
                skipUnknown(inputRange, tagWire.wireType);
                break;
            }
        }
        return result;
    }
}

unittest
{
    static class Foo
    {
        @Proto(1) int bar;
        @Proto(3) bool qux;
        @Proto(2, Wire.fixed) long baz;
    }

    ubyte[] buff = [0x08, 0x05, 0x11, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x01];
    auto foo = buff.fromProtobuf!Foo;
    assert(buff.empty);
    assert(foo.bar == 5);
    assert(foo.baz == 1);
    assert(foo.qux);
}

private static void fromProtobufByField(alias field, T, R)(ref R inputRange, ref T message)
if (isInputRange!R)
{
    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");

    enum proto = protoByField!field;
    static assert(validateProto!(proto, typeof(field)));

    fromProtobufByProto!proto(inputRange, mixin("message." ~ __traits(identifier, field)));
    static if (isOneof!field)
    {
        enum oneofCase = "message." ~ oneofCaseFieldName!field;
        enum fieldCase = "T." ~ typeof(mixin(oneofCase)).stringof ~ "." ~ oneofAccessorName!field;

        mixin(oneofCase) = mixin(fieldCase);
    }
}

private void fromProtobufByProto(Proto proto, T, R)(ref R inputRange, ref T field)
if (isInputRange!R && (isBoolean!T || isFloatingPoint!T || is(T == string) || is(T == bytes)))
{
    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");
    static assert(validateProto!(proto, T));

    field = inputRange.fromProtobuf!T;
}

private void fromProtobufByProto(Proto proto, T, R)(ref R inputRange, ref T field)
if (isInputRange!R && isIntegral!T)
{
    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");
    static assert(validateProto!(proto, T));

    enum wire = proto.wire;
    field = inputRange.fromProtobuf!(T, wire);
}

private void fromProtobufByProto(Proto proto, T, R)(ref R inputRange, ref T field)
if (isInputRange!R && isArray!T && !is(T == string) && !is(T == bytes) && proto.packed)
{
    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");
    static assert(validateProto!(proto, T));

    field ~= inputRange.fromProtobuf!T;
}

private void fromProtobufByProto(Proto proto, T, R)(ref R inputRange, ref T field)
if (isInputRange!R && isArray!T && !is(T == string) && !is(T == bytes) && !proto.packed)
{
    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");
    static assert(validateProto!(proto, T));

    auto newElement = defaultValue!(ElementType!T);
    inputRange.fromProtobufByProto!proto(newElement);
    field ~= newElement;
}

private void fromProtobufByProto(Proto proto, T, R)(ref R inputRange, ref T field)
if (isInputRange!R && isAssociativeArray!T)
{
    import std.conv : to;

    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");
    static assert(validateProto!(proto, T));

    enum keyProto = Proto(MapFieldTag.key, keyWireToWire(proto.wire));
    enum valueProto = Proto(MapFieldTag.value, valueWireToWire(proto.wire));
    KeyType!T key;
    ValueType!T value;
    ubyte decodingState;
    R fieldRange = inputRange.takeLengthPrefixed;

    while (!fieldRange.empty)
    {
        auto tagWire = fieldRange.decodeTag;

        switch (tagWire.tag)
        {
        case MapFieldTag.key:
            enforce!ProtobufException((decodingState & 0x01) == 0, "Double map key");
            decodingState |= 0x01;
            enum wireTypeExpected = wireType!(keyProto, KeyType!T);
            enforce!ProtobufException(tagWire.wireType == wireTypeExpected, "Wrong wire format");
            static if (keyProto.wire == Wire.none)
            {
                key = fieldRange.fromProtobuf!(KeyType!T);
            }
            else
            {
                static assert(isIntegral!(KeyType!T), "Cannot specify wire format for non-integral map key");

                enum wire = keyProto.wire;
                key = fieldRange.fromProtobuf!(KeyType!T, wire);
            }
            break;
        case MapFieldTag.value:
            enforce!ProtobufException((decodingState & 0x02) == 0, "Double map value");
            decodingState |= 0x02;
            enum wireTypeExpected = wireType!(valueProto, KeyType!T);
            enforce!ProtobufException(tagWire.wireType == wireTypeExpected, "Wrong wire format");
            static if (valueProto.wire == Wire.none)
            {
                value = fieldRange.fromProtobuf!(ValueType!T);
            }
            else
            {
                static assert(isIntegral!(ValueType!T), "Cannot specify wire format for non-integral map value");

                enum wire = valueProto.wire;
                value = fieldRange.fromProtobuf!(ValueType!T, wire);
            }
            break;
        default:
            throw new ProtobufException("Unexpected field tag " ~ tagWire.tag.to!string ~ " while decoding a map");
            break;
        }
    }
    enforce!ProtobufException((decodingState & 0x03) == 0x03, "Incomplete map element");
    field[key] = value;
}

private void fromProtobufByProto(Proto proto, T, R)(ref R inputRange, ref T field)
if (isInputRange!R && (is(T == class) || is(T == struct)))
{
    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");
    static assert(validateProto!(proto, T));

    R fieldRange = inputRange.takeLengthPrefixed;

    field = fieldRange.fromProtobuf!T;
}

void skipUnknown(R)(ref R inputRange, WireType wireType)
if (isInputRange!R)
{
    static assert(is(ElementType!R == ubyte), "Input range should be an ubyte range");

    switch (wireType) with (WireType)
    {
    case varint:
        inputRange.fromVarint;
        break;
    case bits64:
        inputRange.takeN(8);
        break;
    case withLength:
        inputRange.takeLengthPrefixed;
        break;
    case bits32:
        inputRange.takeN(4);
        break;
    default:
        enforce!ProtobufException(false, "Unknown wire format");
        break;
    }
}
