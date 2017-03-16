// Generated by the protocol buffer compiler.  DO NOT EDIT!
// source: google/protobuf/struct.proto
module google.protobuf.struct_;

import google.protobuf;

class Struct
{
    @Proto(1) Value[string] fields = defaultValue!(Value[string]);
}

class Value
{
    enum KindCase
    {
        kindNotSet = 0,
        nullValue = 1,
        numberValue = 2,
        stringValue = 3,
        boolValue = 4,
        structValue = 5,
        listValue = 6,
    }
    KindCase _kindCase = KindCase.kindNotSet;
    @property KindCase kindCase() { return _kindCase; }
    void clearKind() { _kindCase = KindCase.kindNotSet; }
    @Oneof("_kindCase") union
    {
        @Proto(1) NullValue _nullValue = defaultValue!(NullValue); mixin(oneofAccessors!_nullValue);
        @Proto(2) double _numberValue; mixin(oneofAccessors!_numberValue);
        @Proto(3) string _stringValue; mixin(oneofAccessors!_stringValue);
        @Proto(4) bool _boolValue; mixin(oneofAccessors!_boolValue);
        @Proto(5) Struct _structValue; mixin(oneofAccessors!_structValue);
        @Proto(6) ListValue _listValue; mixin(oneofAccessors!_listValue);
    }
}

class ListValue
{
    @Proto(1) Value[] values = defaultValue!(Value[]);
}

enum NullValue
{
    NULL_VALUE = 0,
}
