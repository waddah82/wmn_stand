class WmnFrappeException implements Exception {
  const WmnFrappeException(this.message, {this.code = 'FRAPPE_RUNTIME_ERROR'});
  final String message;
  final String code;
  @override
  String toString() => '$code: $message';
}

class WmnFrappeValidationException extends WmnFrappeException {
  const WmnFrappeValidationException(super.message) : super(code: 'VALIDATION_ERROR');
}

class WmnFrappePermissionException extends WmnFrappeException {
  const WmnFrappePermissionException(super.message) : super(code: 'PERMISSION_ERROR');
}

class WmnFrappeDoesNotExistException extends WmnFrappeException {
  const WmnFrappeDoesNotExistException(super.message) : super(code: 'DOES_NOT_EXIST');
}
