// lib/viewmodels/base_view_model.dart
import 'package:flutter/material.dart';

/// An enum to represent the different states of a view/viewmodel.
enum ViewState { idle, loading, error }

/// A base class for ViewModels that provides common state management.
class BaseViewModel extends ChangeNotifier {
  ViewState _state = ViewState.idle;
  ViewState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Sets the current state of the view model and notifies listeners.
  void setState(ViewState viewState) {
    _state = viewState;
    notifyListeners();
  }

  /// Sets the state to error and stores an error message.
  void setError(String message) {
    _errorMessage = message;
    _state = ViewState.error;
    notifyListeners();
  }
}
