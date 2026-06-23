from django import template

register = template.Library()


@register.filter
def naira(value):
    """Format a numeric value as Nigerian Naira: ₦1,234.56"""
    try:
        return f"₦{float(value):,.2f}"
    except (ValueError, TypeError):
        return value


@register.filter
def status_color(status):
    """Return a Bootstrap color class based on job/dispute status."""
    colors = {
        'PENDING': 'warning',
        'ADMIN_APPROVED': 'info',
        'ACCEPTED': 'primary',
        'IN_PROGRESS': 'primary',
        'AWAITING_REVIEW': 'info',
        'COMPLETED': 'success',
        'CANCELLED': 'secondary',
        'DISPUTED': 'danger',
        'REJECTED': 'danger',
        'open': 'danger',
        'in_review': 'warning',
        'resolved': 'success',
        'closed': 'secondary',
        'AVAILABLE': 'success',
        'BUSY': 'warning',
        'ENGAGED': 'info',
        'OFFLINE': 'secondary',
    }
    return colors.get(status, 'secondary')