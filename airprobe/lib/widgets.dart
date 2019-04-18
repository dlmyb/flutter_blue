// Copyright 2017, Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
// import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'dart:typed_data';

class ScanResultTile extends StatelessWidget {
  const ScanResultTile({Key key, this.result, this.onTap}) : super(key: key);

  final ScanResult result;
  final VoidCallback onTap;

  Widget _buildTitle(BuildContext context) {
    if (result.device.name.length > 0) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(result.device.name),
        ],
      );
    } else {
      return Text(result.device.id.toString());
    }
  }

  String getNiceHexArray(List<int> bytes) {
    return '[${bytes.map((i) => i.toRadixString(16).padLeft(2, '0')).join(', ')}]'
        .toUpperCase();
  }

  String getNiceManufacturerData(Map<int, List<int>> data) {
    if (data.isEmpty) {
      return null;
    }
    List<String> res = [];
    data.forEach((id, bytes) {
      res.add(
          '${id.toRadixString(16).toUpperCase()}: ${getNiceHexArray(bytes)}');
    });
    return res.join(', ');
  }

  String getNiceServiceData(Map<String, List<int>> data) {
    if (data.isEmpty) {
      return null;
    }
    List<String> res = [];
    data.forEach((id, bytes) {
      res.add('${id.toUpperCase()}: ${getNiceHexArray(bytes)}');
    });
    return res.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: _buildTitle(context),
      leading: Icon(Icons.bluetooth),
      trailing: RaisedButton(
        child: Text('CONNECT'),
        color: Colors.black,
        textColor: Colors.white,
        onPressed: (result.advertisementData.connectable) ? onTap : null,
      ),
    );
  }
}

class DataRow {
  final double t;
  final double v;
  DataRow(this.t, this.v);
}

class MeasureTile extends StatefulWidget {
  final BluetoothCharacteristic char;
  MeasureTile({Key key, this.char}):super(key: key);

  @override
  _MeasureTileState createState() => new _MeasureTileState();
}

class _MeasureTileState extends State<MeasureTile>{
  List<DataRow> memo;
  int count;
  double startTime;

  @override
  void initState() {
    super.initState();
    memo = new List();
    count = 0;
    startTime = -1;
  }

  @override
  void dispose(){
    memo?.clear();
    memo = null;
    super.dispose();
  }

  List<charts.Series<DataRow, double>> createData(){
    return [new charts.Series<DataRow, double>(
      id: 'Measurement',
      colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
      domainFn: (DataRow r, _) => r.t,
      measureFn: (DataRow r, _) => r.v,
      data: memo,
    )];
  }

  @override
  Widget build(BuildContext context){
    var display = "______";
    if (widget.char != null){
      var values = widget.char.value;
      if (values != null && values.length >= 8 && count >= 7){
        var bdata = ByteData.view(Uint8List.fromList(values).buffer);
        var v = bdata.getFloat32(0, Endian.little);
        var t = bdata.getUint32(4, Endian.little);
        if (startTime == -1) startTime = t/1000;
        if (startTime - t/1000 <= 100) memo.add(DataRow(t/1000 - startTime, v));
        display = v.toStringAsFixed(3);
      }
      else {
        count++;
      }
    }
    if (MediaQuery.of(context).orientation == Orientation.landscape && memo.isNotEmpty){
      return new SizedBox(
          child: new charts.ScatterPlotChart(
            createData(),
            animate: false,
            // defaultRenderer: new charts.LineRendererConfig(includePoints: true),
            domainAxis: new charts.NumericAxisSpec(
              viewport: new charts.NumericExtents(0, 100)
            ),
            primaryMeasureAxis: new charts.NumericAxisSpec(
                tickProviderSpec: new charts.BasicNumericTickProviderSpec(zeroBound: false))
          ),
          height: 250.0
      );
    }
    return MeasureDisplay(value: display);
  }
}

class MeasureDisplay extends StatelessWidget {
  final String value;
  const MeasureDisplay({Key key, this.value}):super(key: key);

  @override
  Widget build(BuildContext context) {
    return new Container(
      alignment: Alignment.center,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 100,
          fontFamily: "digital"
        )
      ),
      height: 400,
    );
  }
}