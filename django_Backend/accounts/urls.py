from django.urls import path
from .views import UserRegistrationAPIView, UserLoginAPIView


urlpatterns = [
    path("register-user/", UserRegistrationAPIView.as_view()),
    path("login-user/", UserLoginAPIView.as_view()),
]