from functools import wraps
from django.shortcuts import redirect


def admin_required(view_func):
    """Redirect to login if not authenticated or not an admin user."""
    @wraps(view_func)
    def wrapper(request, *args, **kwargs):
        if not request.user.is_authenticated:
            return redirect('admin_dashboard:login')
        if request.user.role != 'ADMIN':
            return redirect('admin_dashboard:login')
        return view_func(request, *args, **kwargs)
    return wrapper