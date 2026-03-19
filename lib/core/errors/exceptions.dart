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
  const ServerException(super.message, [this.statusCode]);

  final int? statusCode;

  @override
  List<Object> get props => [...super.props, ?statusCode];
}

class NetworkException extends AppException {
  const NetworkException(super.message);
}

class ValidationException extends AppException {
  const ValidationException(super.message, [this.field]);

  final String? field;

  @override
  List<Object> get props => [...super.props, ?field];
}

class AuthenticationException extends AppException {
  const AuthenticationException(super.message);
}

class AuthorizationException extends AppException {
  const AuthorizationException(super.message);
}

class CacheException extends AppException {
  const CacheException(super.message);
}

class AppStorageException extends AppException {
  const AppStorageException(super.message, [this.path]);

  final String? path;

  @override
  List<Object> get props => [...super.props, ?path];
}

class ParseException extends AppException {
  const ParseException(super.message);
}

class UnknownException extends AppException {
  const UnknownException(super.message);
}
