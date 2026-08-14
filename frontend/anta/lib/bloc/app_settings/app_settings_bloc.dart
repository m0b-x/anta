import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import '../../database/database.dart';
import '../../constants/settings_keys.dart';

// Events
abstract class AppSettingsEvent extends Equatable {
  const AppSettingsEvent();

  @override
  List<Object?> get props => [];
}

class LoadAppSettings extends AppSettingsEvent {
  const LoadAppSettings();
}

class ChangeLocale extends AppSettingsEvent {
  final String? localeCode; // null means system default

  const ChangeLocale(this.localeCode);

  @override
  List<Object?> get props => [localeCode];
}

class ChangeThemeMode extends AppSettingsEvent {
  final ThemeMode themeMode;

  const ChangeThemeMode(this.themeMode);

  @override
  List<Object?> get props => [themeMode];
}

// State
class AppSettingsState extends Equatable {
  final String? localeCode; // null means system default
  final ThemeMode themeMode;
  final bool isLoading;

  const AppSettingsState({
    this.localeCode,
    this.themeMode = ThemeMode.system,
    this.isLoading = true,
  });

  AppSettingsState copyWith({
    String? localeCode,
    bool clearLocale = false,
    ThemeMode? themeMode,
    bool? isLoading,
  }) {
    return AppSettingsState(
      localeCode: clearLocale ? null : (localeCode ?? this.localeCode),
      themeMode: themeMode ?? this.themeMode,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  Locale? get locale => localeCode != null ? Locale(localeCode!) : null;

  @override
  List<Object?> get props => [localeCode, themeMode, isLoading];
}

// BLoC
class AppSettingsBloc extends Bloc<AppSettingsEvent, AppSettingsState> {
  AppSettingsBloc() : super(const AppSettingsState()) {
    on<LoadAppSettings>(_onLoadSettings);
    on<ChangeLocale>(_onChangeLocale);
    on<ChangeThemeMode>(_onChangeThemeMode);
  }

  Future<void> _onLoadSettings(
    LoadAppSettings event,
    Emitter<AppSettingsState> emit,
  ) async {
    try {
      final db = await AppDatabase.getInstance();
      final localeCode = await db.userSettingsDao.getValue(SettingsKeys.locale);
      final themeModeStr = await db.userSettingsDao.getValue(
        SettingsKeys.themeMode,
      );

      final themeMode = _parseThemeMode(themeModeStr);

      emit(
        state.copyWith(
          localeCode: localeCode,
          clearLocale: localeCode == null,
          themeMode: themeMode,
          isLoading: false,
        ),
      );
    } catch (e) {
      // Default to system settings on error
      emit(state.copyWith(isLoading: false, clearLocale: true));
    }
  }

  Future<void> _onChangeLocale(
    ChangeLocale event,
    Emitter<AppSettingsState> emit,
  ) async {
    try {
      final db = await AppDatabase.getInstance();

      if (event.localeCode == null) {
        await db.userSettingsDao.deleteValue(SettingsKeys.locale);
        emit(state.copyWith(clearLocale: true));
      } else {
        await db.userSettingsDao.setValue(
          SettingsKeys.locale,
          event.localeCode!,
        );
        emit(state.copyWith(localeCode: event.localeCode));
      }
    } catch (e) {
      // Ignore errors, keep current state
    }
  }

  Future<void> _onChangeThemeMode(
    ChangeThemeMode event,
    Emitter<AppSettingsState> emit,
  ) async {
    try {
      final db = await AppDatabase.getInstance();
      await db.userSettingsDao.setValue(
        SettingsKeys.themeMode,
        _themeModeToString(event.themeMode),
      );
      emit(state.copyWith(themeMode: event.themeMode));
    } catch (e) {
      // Ignore errors, keep current state
    }
  }

  ThemeMode _parseThemeMode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
