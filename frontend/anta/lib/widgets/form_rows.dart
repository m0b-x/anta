import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/form_metrics.dart';
import '../constants/row_metrics.dart';
import 'automation_id.dart';
import 'form_menu_item.dart';
import 'settings_reorder.dart';

export '../constants/form_metrics.dart';
export 'form_menu_item.dart' show FormMenuItem;
export 'form_sheet_frame.dart';

// The row primitives are parts of this one library, a file per family:
// callers keep a single import, and the families keep sharing the private
// helpers a row is laid out with.
part 'form_rows/row_groups.dart';
part 'form_rows/labels_and_captions.dart';
part 'form_rows/sheet_header.dart';
part 'form_rows/row_pieces.dart';
part 'form_rows/picker_rows.dart';
part 'form_rows/title_rows.dart';
part 'form_rows/choice_rows.dart';
part 'form_rows/action_row.dart';
part 'form_rows/meter_and_stepper_rows.dart';
part 'form_rows/chips.dart';
part 'form_rows/search_row.dart';
