from rest_framework.permissions import BasePermission


class IsAdminRole(BasePermission):
    """Allow access only to users with role=ADMIN.

    This checks the custom role field instead of Django's is_staff,
    so it works for admins created through the registration flow
    (who have role=ADMIN but may not have is_staff=True).
    """

    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role == 'ADMIN'
        )