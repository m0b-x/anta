/// A sealed Result type for type-safe error handling.
///
/// Usage:
/// ```dart
/// final result = await repository.getNoteById(id);
/// switch (result) {
///   case Success(:final data):
///     print('Got note: ${data.title}');
///   case Failure(:final error):
///     print('Error: ${error.message}');
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// Returns true if this is a Success result
  bool get isSuccess => this is Success<T>;

  /// Returns true if this is a Failure result
  bool get isFailure => this is Failure<T>;

  /// Returns the data if Success, throws if Failure
  T get dataOrThrow {
    return switch (this) {
      Success(:final data) => data,
      Failure(:final error) => throw error,
    };
  }

  /// Returns the data if Success, or null if Failure
  T? get dataOrNull {
    return switch (this) {
      Success(:final data) => data,
      Failure() => null,
    };
  }

  /// Returns the error if Failure, or null if Success
  AppError? get errorOrNull {
    return switch (this) {
      Success() => null,
      Failure(:final error) => error,
    };
  }

  /// Maps the success value to a new type
  Result<R> map<R>(R Function(T data) transform) {
    return switch (this) {
      Success(:final data) => Success(transform(data)),
      Failure(:final error) => Failure(error),
    };
  }

  /// Maps the success value to a new Result
  Result<R> flatMap<R>(Result<R> Function(T data) transform) {
    return switch (this) {
      Success(:final data) => transform(data),
      Failure(:final error) => Failure(error),
    };
  }

  /// Executes the given function if Success
  Result<T> onSuccess(void Function(T data) action) {
    if (this case Success(:final data)) {
      action(data);
    }
    return this;
  }

  /// Executes the given function if Failure
  Result<T> onFailure(void Function(AppError error) action) {
    if (this case Failure(:final error)) {
      action(error);
    }
    return this;
  }

  /// Returns the result of [onSuccess] if Success, or [onFailure] if Failure
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(AppError error) onFailure,
  }) {
    return switch (this) {
      Success(:final data) => onSuccess(data),
      Failure(:final error) => onFailure(error),
    };
  }
}

/// Represents a successful result containing data
final class Success<T> extends Result<T> {
  final T data;

  const Success(this.data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T> &&
          runtimeType == other.runtimeType &&
          data == other.data;

  @override
  int get hashCode => data.hashCode;

  @override
  String toString() => 'Success($data)';
}

/// Represents a failed result containing an error
final class Failure<T> extends Result<T> {
  final AppError error;

  const Failure(this.error);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure<T> &&
          runtimeType == other.runtimeType &&
          error == other.error;

  @override
  int get hashCode => error.hashCode;

  @override
  String toString() => 'Failure($error)';
}

/// Sealed class hierarchy for application errors
sealed class AppError implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  const AppError(this.message, {this.cause, this.stackTrace});

  @override
  String toString() => '$runtimeType: $message';
}

/// Database-related errors
final class DatabaseError extends AppError {
  const DatabaseError(super.message, {super.cause, super.stackTrace});
}

/// Entity not found errors
final class NotFoundError extends AppError {
  final String entityType;
  final String? entityId;

  const NotFoundError(
    super.message, {
    required this.entityType,
    this.entityId,
    super.cause,
    super.stackTrace,
  });
}

/// Validation errors
final class ValidationError extends AppError {
  final Map<String, String>? fieldErrors;

  const ValidationError(
    super.message, {
    this.fieldErrors,
    super.cause,
    super.stackTrace,
  });
}

/// Network-related errors (for future sync)
final class NetworkError extends AppError {
  final int? statusCode;

  const NetworkError(
    super.message, {
    this.statusCode,
    super.cause,
    super.stackTrace,
  });
}

/// Cache-related errors
final class CacheError extends AppError {
  const CacheError(super.message, {super.cause, super.stackTrace});
}

/// Permission errors
final class PermissionError extends AppError {
  const PermissionError(super.message, {super.cause, super.stackTrace});
}

/// Unknown/unexpected errors
final class UnknownError extends AppError {
  const UnknownError(super.message, {super.cause, super.stackTrace});
}

/// Extension to easily create Results
extension ResultExtension<T> on T {
  Result<T> get asSuccess => Success(this);
}

/// Extension to easily wrap async operations in Result
extension FutureResultExtension<T> on Future<T> {
  Future<Result<T>> toResult() async {
    try {
      return Success(await this);
    } catch (e, st) {
      return Failure(UnknownError(e.toString(), cause: e, stackTrace: st));
    }
  }
}
