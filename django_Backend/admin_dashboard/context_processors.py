def dashboard_context(request):
    """Add common context variables to all dashboard templates."""
    context = {
        'naira_symbol': '₦',
        'app_name': 'Fix-It Admin',
    }
    if request.user.is_authenticated and request.user.role == 'ADMIN':
        context['admin_user'] = request.user
    return context