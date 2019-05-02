// Copyright 2017, Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
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
  List<double> filter;
  int n;
  int count;
  double startTime;
  double _time;
  double _measure;
  int _flag;
  final _s = const ['_', 'mV', 'V', 'V', 'V', 'mA', 'Ω', 'kΩ', 'MΩ'];
  final _b = const [-1, 2, 2, 2, 3, 5, 6];
  final _r = const ['_', 'DC: 0 - 20mV', 'DC: 0 - 2V', 'DC: 0 - 20V', 'AC: 100 - 220V', 'Cur: 0 - 20mA', 'Res: 0 - 1MΩ'];
  final _limit = const [1e6, 1e2, 1e3, 20, 220, 20, 1e6, 1e6, 1e6];

  @override
  void initState() {
    super.initState();
    memo = new List();
    count = 0;
    _flag = 0;
    n = 0;
    filter = <double>[0, 0, 0, 0, 0];
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

  _onSelectionChanged(charts.SelectionModel model) {
    final selectedDatum = model.selectedDatum;  
    
    double time, measure;
    if (selectedDatum.isNotEmpty) {
      time = selectedDatum.first.datum.t;
      measure = selectedDatum.first.datum.v;
    }

    // Request a build.
    setState(() {
      _time = time;
      _measure = measure;
    });
  }

  @override
  Widget build(BuildContext context){
    var display = "______";
    var range = "_____";
    var _f = " ";
    if (widget.char != null){
      var values = widget.char.value;
      // count: when connection was estabilished, airprobe needs few seconds stand by.
      if (values != null && values.length >= 8 && count >= 7){
        var bdata = ByteData.view(Uint8List.fromList(values).buffer);
        var t = bdata.getUint32(0, Endian.little) & (0xfffffff);
        var flag = bdata.getUint32(0, Endian.little) >> 28;
        var v = bdata.getFloat32(4, Endian.little);

        // clear memo and filter, 
        if (_flag == 0 || _b[_flag] != _b[flag]){
          count = 5;
          startTime = -1;
          n = 0;
          memo.clear();
          _flag = flag;
        }
        if (v < 0) v = 0;
        filter[n%filter.length] = v;
        var rv = filter.reduce((a, b) => a + b) / filter.length;

        if (n > filter.length && rv < _limit[flag]){
          n = n % filter.length + filter.length;
          if (startTime == -1) startTime = t/1000;
          // logging data for 60s
          if (startTime - t/1000 <= 60){
            var vv = rv;
            if (flag == 1) vv /= 1000;
            memo.add(DataRow(t/1000 - startTime, vv));
          }

          range = _r[flag];
          
          // for residence
          while (rv >= 1000 && flag >= 6 && flag < _s.length - 1){
            flag += 1;
            rv /= 1000;
          }

          display = rv.toStringAsFixed(2);
          _f = _s[flag];
        }

        // beyond limitation
        if (rv >= _limit[flag]){
          display = "";
          range = _r[flag];
          _f = "OVERLOAD";
        }
        // self add for next filter update.
        n += 1;
      }
      else {
        count++;
      }
    }
    if (MediaQuery.of(context).orientation == Orientation.landscape && memo.isNotEmpty){
      final children = <Widget>[SizedBox(
          child: new charts.ScatterPlotChart(
            createData(),
            animate: false,
            // defaultRenderer: new charts.LineRendererConfig(includePoints: true),
            domainAxis: new charts.NumericAxisSpec(
              viewport: new charts.NumericExtents(0, 60)
            ),
            primaryMeasureAxis: new charts.NumericAxisSpec(
                tickProviderSpec: new charts.BasicNumericTickProviderSpec(zeroBound: false)),
            selectionModels: [
              new charts.SelectionModelConfig(
                type: charts.SelectionModelType.info,
                changedListener: _onSelectionChanged,
              )
            ],
            behaviors: [
              new charts.LinePointHighlighter(
                showHorizontalFollowLine:
                  charts.LinePointHighlighterFollowLineType.nearest,
                showVerticalFollowLine:
                  charts.LinePointHighlighterFollowLineType.nearest),
              new charts.SelectNearest(
                eventTrigger: charts.SelectionTrigger.tapAndDrag),
            ],
          ),
          height: 200.0
      )];
      if (_time != null){
        children.add(new Padding(
          padding: new EdgeInsets.only(top: 5.0),
          child: new Text("Time: ${_time.toStringAsFixed(3)} s")
        ));
        children.add(
          new Text("Measure: ${_measure.toStringAsFixed(3)} ${_s[_b[_flag]]}")
        );
      }
      return new Column(children: children);
    }
    return MeasureDisplay(value: display, flag: _f, range: range);
  }
}

class MeasureDisplay extends StatelessWidget {
  final String value;
  final String flag;
  final String range;
  const MeasureDisplay({Key key, this.value, this.flag, this.range}):super(key: key);

  @override
  Widget build(BuildContext context) {
    var children = <Widget>[
      Padding(padding: new EdgeInsets.only(top: 20.0)),
      Text(value, 
          style: TextStyle(
          fontSize: 80,
          // fontFamily: "digital"
        )
      ),
      Text(flag, style: TextStyle(fontSize: 60)),
      Padding(padding: new EdgeInsets.only(top: 20.0)),
      Text(range, style: TextStyle(fontSize: 30),)
    ];
    return new Container(
      alignment: Alignment.center,
      child: new Column(children: children),
      height: 400,
    );
  }
}