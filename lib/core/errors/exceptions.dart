import 'package:equatable/equatable.dart';

abstract class AppException extends Equatable implements Exception {
  const AppException(this.message);

  final String message;

  @override
  List<Object> get props => [message];

  @override
  String toString() => message;
}

class ServerException extends AppException {
  const ServerException(String message, [this.statusCode]) : super(message);

  final int? statusCode;

  @override
  List<Object> get props => [...super.props, statusCode];
}

class NetworkException extends AppException {
  const NetworkException(String message) : super(message);
}

class ValidationException extends AppException {
  const ValidationException(String message, [this.field]) : super(message);

  final String? field;

  @override
  List<Object> get props => [...super.props, field];
}

class AuthenticationException extends AppException {
  const AuthenticationException(String message) : super(message);
}

class AuthorizationException extends AppException {
  const AuthorizationException(String message) : super(message);
}

class CacheException extends AppException {
  const CacheException(String message) : super(message);
}

class StorageException extends AppException {
  const StorageException(String message, [this.path]) : super(message);

  final String? path;

  @override
  List<Object> get props => [...super.props, path];
}

class ParseException extends AppException {
  const ParseException(String message) : super(message);
}

class UnknownException extends AppException {
  const UnknownException(String message) : super(message);
}
