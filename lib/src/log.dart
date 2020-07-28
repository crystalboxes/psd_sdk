const PSD_ENABLE_LOGGING = true;

void psdWarning(List<String> args) {
  if (PSD_ENABLE_LOGGING) {
    final channel = args[0];
    final msg = args.sublist(1).reduce((value, element) => '$value $element');
    setLastError(msg);
    print('***WARNING*** [$channel] ${msg}');
  }
}

void psdError(List<String> args) {
  if (PSD_ENABLE_LOGGING) {
    final channel = args[0];
    final msg = args.sublist(1).reduce((value, element) => '$value $element');
    setLastError(msg);
    print('***ERROR*** [$channel] ${msg}');
  }
}

var lastError = '';

void setLastError(String err) {
  lastError = err;
}
