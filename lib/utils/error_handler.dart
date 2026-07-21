/// User-friendly error message handler for all screens
/// Converts technical/database errors to user-friendly messages
class ErrorHandler {
  /// Convert exception to user-friendly message
  static String getUserFriendlyMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // Database/SQL errors
    if (errorStr.contains('integrity constraint violation') ||
        errorStr.contains('sqlstate')) {
      if (errorStr.contains('cannot be null')) {
        return 'Please fill in all required fields';
      }
      if (errorStr.contains('duplicate entry') ||
          errorStr.contains('unique')) {
        return 'This record already exists in the system';
      }
      return 'Database error. Please try again or contact support';
    }

    // Connection errors
    if (errorStr.contains('connection') ||
        errorStr.contains('unable to connect') ||
        errorStr.contains('socket')) {
      return 'Network connection error. Please check your internet connection';
    }

    // Authentication errors
    if (errorStr.contains('unauthorized') ||
        errorStr.contains('unauthenticated') ||
        errorStr.contains('invalid credentials')) {
      return 'Invalid username or password';
    }

    // Validation errors
    if (errorStr.contains('validation') ||
        errorStr.contains('invalid input')) {
      return 'Please check your input and try again';
    }

    // Server errors
    if (errorStr.contains('500') ||
        errorStr.contains('internal server error')) {
      return 'Server error. Please try again later';
    }

    if (errorStr.contains('404') ||
        errorStr.contains('not found')) {
      return 'Record not found. Please check and try again';
    }

    // Timeout errors
    if (errorStr.contains('timeout') ||
        errorStr.contains('timed out')) {
      return 'Request took too long. Please try again';
    }

    // Generic fallback
    return 'An error occurred. Please try again or contact support';
  }

  /// Extract clean error message by removing 'Exception: ' prefix
  static String cleanMessage(dynamic error) {
    final str = error.toString();
    if (str.startsWith('Exception: ')) {
      return str.replaceFirst('Exception: ', '');
    }
    return str;
  }
}
