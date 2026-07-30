import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';

class ImportExportService {
  /// Prompts the user to save an Excel file to a location on their computer.
  static Future<bool> exportExcel({
    required BuildContext context,
    required String defaultFileName,
    required Map<String, List<List<dynamic>>> sheets,
  }) async {
    try {
      final excel = Excel.createExcel();

      // Populate the sheets
      bool isFirst = true;
      for (final entry in sheets.entries) {
        final sheetName = entry.key;
        final rows = entry.value;

        Sheet sheet;
        if (isFirst) {
          excel.rename('Sheet1', sheetName);
          sheet = excel[sheetName];
          isFirst = false;
        } else {
          sheet = excel[sheetName];
        }

        for (final row in rows) {
          final cellValues = row.map((cell) {
            if (cell == null) return TextCellValue('');
            if (cell is int) return IntCellValue(cell);
            if (cell is double) return DoubleCellValue(cell);
            if (cell is bool) return BoolCellValue(cell);
            return TextCellValue(cell.toString());
          }).toList();
          sheet.appendRow(cellValues);
        }
      }

      final fileBytes = excel.save();
      if (fileBytes == null) return false;

      final outputFile = await FilePicker.saveFile(
        dialogTitle: 'Select Location to Save Excel Sheet',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile == null) {
        return false;
      }

      final file = File(outputFile);
      await file.writeAsBytes(fileBytes);
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel Export failed: ${e.toString()}')),
        );
      }
      return false;
    }
  }

  /// Prompts the user to save a JSON backup file to a location on their computer.
  static Future<bool> exportBackup({
    required BuildContext context,
    required String defaultFileName,
    required String jsonContent,
  }) async {
    try {
      // Use FilePicker to select where to save the JSON backup
      final outputFile = await FilePicker.saveFile(
        dialogTitle: 'Select Location to Save Backup',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (outputFile == null) {
        // User cancelled
        return false;
      }

      final file = File(outputFile);
      await file.writeAsString(jsonContent);
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.toString()}')),
        );
      }
      return false;
    }
  }

  /// Prompts the user to select a JSON file from their computer and returns its content.
  static Future<String?> importBackup({required BuildContext context}) async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Select JSON Backup File to Restore',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        // User cancelled
        return null;
      }

      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      return content;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read file: ${e.toString()}')),
        );
      }
      return null;
    }
  }

  /// Prompts the user to select an Excel (.xlsx) file and returns an Excel object.
  static Future<Excel?> importExcel({required BuildContext context}) async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Select Excel (.xlsx) Backup File to Restore',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null || result.files.single.path == null) {
        return null;
      }

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      return excel;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read Excel file: ${e.toString()}')),
        );
      }
      return null;
    }
  }

  /// Parses a given sheet in an Excel workbook into a List of Map<String, dynamic>.
  static List<Map<String, dynamic>> parseSheet({
    required Excel excel,
    required String sheetName,
  }) {
    final sheet = excel.tables[sheetName];
    if (sheet == null || sheet.maxRows <= 1) return [];

    final rows = sheet.rows;
    final headerRow = rows[0];
    final List<String> headers = headerRow.map<String>((cell) {
      final val = cell?.value;
      if (val == null) return '';
      if (val is TextCellValue) return (val.value.text ?? '').trim();
      try {
        return (val as dynamic).value.toString().trim();
      } catch (_) {
        return val.toString().trim();
      }
    }).toList();

    final List<Map<String, dynamic>> data = [];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      final Map<String, dynamic> rowMap = {};
      for (int j = 0; j < headers.length; j++) {
        if (headers[j].isEmpty) continue;
        final cellValue = j < row.length ? row[j]?.value : null;
        if (cellValue == null) {
          rowMap[headers[j]] = null;
        } else {
          if (cellValue is TextCellValue) {
            rowMap[headers[j]] = cellValue.value.text ?? '';
          } else if (cellValue is IntCellValue) {
            rowMap[headers[j]] = cellValue.value;
          } else if (cellValue is DoubleCellValue) {
            rowMap[headers[j]] = cellValue.value;
          } else if (cellValue is BoolCellValue) {
            rowMap[headers[j]] = cellValue.value;
          } else {
            try {
              rowMap[headers[j]] = (cellValue as dynamic).value;
            } catch (_) {
              rowMap[headers[j]] = cellValue.toString();
            }
          }
        }
      }
      data.add(rowMap);
    }
    return data;
  }
}
