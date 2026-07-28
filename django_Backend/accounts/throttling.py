from rest_framework.throttling import AnonRateThrottle, UserRateThrottle


class LoginRateThrottle(AnonRateThrottle):
    """Rate limit for login attempts: 5 per minute per IP address.
    Prevents brute-force password attacks."""
    rate = '5/min'


class RegisterRateThrottle(AnonRateThrottle):
    """Rate limit for registration: 3 per hour per IP address.
    Prevents automated account creation."""
    rate = '3/hour'


class PasswordChangeRateThrottle(UserRateThrottle):
    """Rate limit for password changes: 3 per hour per user.
    Prevents abuse of the password change endpoint."""
    rate = '3/hour'


class PasswordResetRateThrottle(AnonRateThrottle):
    """Rate limit for password reset requests: 3 per hour per IP address.
    Prevents abuse of the forgot-password endpoint."""
    rate = '3/hour'


class OTPVerifyRateThrottle(AnonRateThrottle):
    """Rate limit for OTP verification attempts: 10 per minute per IP address.
    Prevents brute-force OTP guessing. Combined with per-OTP lockout
    (5 wrong attempts = locked), this provides strong protection."""
    rate = '10/min'


class EmailVerifyRateThrottle(AnonRateThrottle):
    """Rate limit for email verification requests: 5 per hour per IP address.
    Prevents abuse of the email verification endpoint."""
    rate = '5/hour'


class ResendEmailVerifyRateThrottle(AnonRateThrottle):
    """Rate limit for resending verification emails: 3 per hour per IP address.
    Prevents spamming verification emails."""
    rate = '3/hour'