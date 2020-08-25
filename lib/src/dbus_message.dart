import 'dbus_value.dart';
import 'dbus_read_buffer.dart';
import 'dbus_write_buffer.dart';

const ProtocolVersion = 1;

class Endianess {
  static const Little = 108; // ASCII 'l'
  static const Big = 66; // ASCII 'B'
}

class HeaderCode {
  static const Invalid = 0;
  static const Path = 1;
  static const Interface = 2;
  static const Member = 3;
  static const ErrorName = 4;
  static const ReplySerial = 5;
  static const Destination = 6;
  static const Sender = 7;
  static const Signature = 8;
  static const UnixFds = 9;
}

class MessageType {
  static const Invalid = 0;
  static const MethodCall = 1;
  static const MethodReturn = 2;
  static const Error = 3;
  static const Signal = 4;
}

class Flags {
  static const NoReplyExpected = 0x01;
  static const NoAutoStart = 0x02;
  static const AllowInteractiveAuthorization = 0x04;
}

class DBusMessage {
  int type;
  int flags;
  int serial;
  DBusObjectPath path;
  String interface;
  String member;
  String errorName;
  int replySerial;
  String destination;
  String sender;
  var values = <DBusValue>[];

  DBusMessage(
      {this.type = MessageType.Invalid,
      this.flags = 0,
      this.serial = 0,
      this.path,
      this.interface,
      this.member,
      this.errorName,
      this.replySerial,
      this.destination,
      this.sender,
      this.values});

  void marshal(DBusWriteBuffer buffer) {
    var valueBuffer = DBusWriteBuffer();
    for (var value in values) {
      valueBuffer.writeValue(value);
    }

    // FIXME(robert-ancell): Handle endianess - currently hard-coded to little
    buffer.writeValue(DBusByte(Endianess.Little));
    buffer.writeValue(DBusByte(type));
    buffer.writeValue(DBusByte(flags));
    buffer.writeValue(DBusByte(ProtocolVersion));
    buffer.writeValue(DBusUint32(valueBuffer.data.length));
    buffer.writeValue(DBusUint32(serial));
    var headers = <DBusValue>[];
    if (path != null) {
      headers.add(_makeHeader(HeaderCode.Path, path));
    }
    if (interface != null) {
      headers.add(_makeHeader(HeaderCode.Interface, DBusString(interface)));
    }
    if (member != null) {
      headers.add(_makeHeader(HeaderCode.Member, DBusString(member)));
    }
    if (errorName != null) {
      headers.add(_makeHeader(HeaderCode.ErrorName, DBusString(errorName)));
    }
    if (replySerial != null) {
      headers.add(_makeHeader(HeaderCode.ReplySerial, DBusUint32(replySerial)));
    }
    if (destination != null) {
      headers.add(_makeHeader(HeaderCode.Destination, DBusString(destination)));
    }
    if (sender != null) {
      headers.add(_makeHeader(HeaderCode.Sender, DBusString(sender)));
    }
    if (values.isNotEmpty) {
      var signature = '';
      for (var value in values) {
        signature += value.signature.value;
      }
      headers.add(_makeHeader(HeaderCode.Signature, DBusSignature(signature)));
    }
    buffer.writeValue(DBusArray(DBusSignature('(yv)'), headers));
    buffer.align(8);
    buffer.writeBytes(valueBuffer.data);
  }

  DBusStruct _makeHeader(int code, DBusValue value) {
    return DBusStruct([DBusByte(code), DBusVariant(value)]);
  }

  bool unmarshal(DBusReadBuffer buffer) {
    if (buffer.remaining < 12) return false;

    buffer.readDBusByte(); // Endianess.
    type = buffer.readDBusByte().value;
    flags = buffer.readDBusByte().value;
    buffer.readDBusByte(); // Protocol version.
    var dataLength = buffer.readDBusUint32();
    serial = buffer.readDBusUint32().value;
    var headers = buffer.readDBusArray(DBusSignature('(yv)'));
    if (headers == null) return false;

    DBusSignature signature;
    for (var child in headers.children) {
      var header = child as DBusStruct;
      var code = (header.children.elementAt(0) as DBusByte).value;
      var value = (header.children.elementAt(1) as DBusVariant).value;
      if (code == HeaderCode.Path) {
        path = value as DBusObjectPath;
      } else if (code == HeaderCode.Interface) {
        interface = (value as DBusString).value;
      } else if (code == HeaderCode.Member) {
        member = (value as DBusString).value;
      } else if (code == HeaderCode.ErrorName) {
        errorName = (value as DBusString).value;
      } else if (code == HeaderCode.ReplySerial) {
        replySerial = (value as DBusUint32).value;
      } else if (code == HeaderCode.Destination) {
        destination = (value as DBusString).value;
      } else if (code == HeaderCode.Sender) {
        sender = (value as DBusString).value;
      } else if (code == HeaderCode.Signature) {
        signature = value as DBusSignature;
      }
    }
    if (!buffer.align(8)) return false;

    if (buffer.remaining < dataLength.value) {
      return false;
    }

    values = <DBusValue>[];
    if (signature != null) {
      var signatures = signature.split();
      for (var s in signatures) {
        var value = buffer.readDBusValue(s);
        if (value == null) return false;
        values.add(value);
      }
    }

    return true;
  }

  @override
  String toString() {
    var text = 'DBusMessage(type=';
    if (type == MessageType.MethodCall) {
      text += 'MessageType.MethodCall';
    } else if (type == MessageType.MethodReturn) {
      text += 'MessageType.MethodReturn';
    } else if (type == MessageType.Error) {
      text += 'MessageType.Error';
    } else if (type == MessageType.Signal) {
      text += 'MessageType.Signal';
    } else {
      text += '${type}';
    }
    if (flags != 0) {
      var flagNames = <String>[];
      if (flags & Flags.NoReplyExpected != 0) {
        flagNames.add('Flags.NoReplyExpected');
      }
      if (flags & Flags.NoAutoStart != 0) {
        flagNames.add('Flags.NoAutoStart');
      }
      if (flags & Flags.AllowInteractiveAuthorization != 0) {
        flagNames.add('Flags.AllowInteractiveAuthorization');
      }
      if (flags & 0xF8 != 0) {
        flagNames.add((flags & 0xF8).toRadixString(16).padLeft(2));
      }
      text += ' flags=${flagNames.join('|')}';
    }
    text += ' serial=${serial}';
    if (path != null) text += ", path='${path}'";
    if (interface != null) text += ", interface='${interface}'";
    if (member != null) text += ", member='${member}'";
    if (errorName != null) text += ", errorName='${errorName}'";
    if (replySerial != null) text += ', replySerial=${replySerial}';
    if (destination != null) text += ", destination='${destination}'";
    if (sender != null) text += ", sender='${sender}'";
    if (values.isNotEmpty) {
      var valueText = <String>[];
      for (var value in values) {
        valueText.add(value.toString());
      }
      text += ", values=[${valueText.join(', ')}]";
    }
    text += ')';
    return text;
  }
}
