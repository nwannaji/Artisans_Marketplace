import logging

from django.contrib.auth import authenticate, login, logout
from django.contrib import messages
from django.db.models import Count, Q
from django.utils import timezone
from datetime import timedelta
from django.db import transaction as db_transaction
from django.shortcuts import get_object_or_404, redirect, render
from django.views.decorators.http import require_POST
from django.core.paginator import Paginator
from .decorators import admin_required
from .forms import LoginForm, DisputeResolveForm, ChatMessageForm, UserEditForm, CustomerProfileEditForm, ArtisanProfileEditForm, UserDeleteConfirmForm, SubscriptionActivateForm
from accounts.models import User, ArtisanProfile, CustomerProfile
from bookings.models import Job
from chats.models import Conversation, Chat
from disputes.models import Dispute
from reviews.models import Review
from subscriptions.models import Subscription

logger = logging.getLogger(__name__)


# ========================
# Auth Views
# ========================

def dashboard_login(request):
    """Admin dashboard login using Django session auth."""
    if request.user.is_authenticated and request.user.role == User.Role.ADMIN:
        return redirect('admin_dashboard:overview')

    if request.method == 'POST':
        form = LoginForm(request.POST)
        if form.is_valid():
            username = form.cleaned_data['username']
            password = form.cleaned_data['password']
            user = authenticate(request, username=username, password=password)
            if user is not None and user.is_active and user.role == User.Role.ADMIN:
                login(request, user)
                next_url = request.GET.get('next', '')
                return redirect(next_url or 'admin_dashboard:overview')
            else:
                error = 'Invalid credentials or not an admin account.'
                if user and not user.is_active:
                    error = 'Your account is not active. Contact another admin.'
                elif user and user.role != User.Role.ADMIN:
                    error = 'This dashboard is for admin accounts only.'
                return render(request, 'admin_dashboard/login.html', {'form': form, 'error': error})
    else:
        form = LoginForm()

    return render(request, 'admin_dashboard/login.html', {'form': form})


@admin_required
def dashboard_logout(request):
    """Log out and redirect to login page."""
    logout(request)
    return redirect('admin_dashboard:login')


# ========================
# Dashboard Overview
# ========================

@admin_required
def dashboard_overview(request):
    """Main dashboard with key metrics and recent activity."""
    total_users = User.objects.count()
    active_users = User.objects.filter(is_active=True).count()
    total_customers = User.objects.filter(role=User.Role.CUSTOMER).count()
    total_artisans = ArtisanProfile.objects.count()
    verified_artisans = ArtisanProfile.objects.filter(is_verified=True).count()
    unverified_artisans = ArtisanProfile.objects.filter(is_verified=False).count()

    job_status_counts = dict(
        Job.objects.values('status').annotate(count=Count('id')).values_list('status', 'count')
    )

    open_disputes = Dispute.objects.filter(
        status__in=[Dispute.Status.OPEN, Dispute.Status.IN_REVIEW]
    ).count()

    recent_jobs = Job.objects.select_related(
        'customer', 'artisan__user'
    ).order_by('-created_at')[:10]

    recent_disputes = Dispute.objects.select_related(
        'job__customer', 'job__artisan__user'
    ).order_by('-created_at')[:5]

    # Subscription stats
    now = timezone.now()
    active_pro = Subscription.objects.filter(
        tier__in=[Subscription.Tier.PRO, Subscription.Tier.PREMIUM],
    ).filter(
        Q(expires_at__isnull=True) | Q(expires_at__gt=now)
    ).count()
    active_premium = Subscription.objects.filter(
        tier=Subscription.Tier.PREMIUM,
    ).filter(
        Q(expires_at__isnull=True) | Q(expires_at__gt=now)
    ).count()
    free_tier_artisans = ArtisanProfile.objects.filter(
        subscription__isnull=True
    ).count() + Subscription.objects.filter(
        tier=Subscription.Tier.FREE,
    ).count()

    context = {
        'total_users': total_users,
        'active_users': active_users,
        'total_customers': total_customers,
        'total_artisans': total_artisans,
        'verified_artisans': verified_artisans,
        'unverified_artisans': unverified_artisans,
        'pending_jobs': job_status_counts.get(Job.Status.PENDING, 0),
        'approved_jobs': job_status_counts.get(Job.Status.ADMIN_APPROVED, 0),
        'active_jobs': job_status_counts.get(Job.Status.IN_PROGRESS, 0),
        'completed_jobs': job_status_counts.get(Job.Status.COMPLETED, 0),
        'cancelled_jobs': job_status_counts.get(Job.Status.CANCELLED, 0),
        'disputed_jobs': job_status_counts.get(Job.Status.DISPUTED, 0),
        'open_disputes': open_disputes,
        'recent_jobs': recent_jobs,
        'recent_disputes': recent_disputes,
        'active_pro_subscriptions': active_pro,
        'active_premium_subscriptions': active_premium,
        'free_tier_artisans': free_tier_artisans,
    }
    return render(request, 'admin_dashboard/dashboard.html', context)


# ========================
# User Management
# ========================

@admin_required
def user_list(request):
    """Paginated list of all users with search and role filter."""
    search = request.GET.get('search', '')
    role_filter = request.GET.get('role', '')
    active_filter = request.GET.get('is_active', '')

    qs = User.objects.select_related('artisanprofile', 'customerprofile').all()

    if search:
        qs = qs.filter(Q(username__icontains=search) | Q(email__icontains=search))
    if role_filter:
        qs = qs.filter(role=role_filter)
    if active_filter == 'true':
        qs = qs.filter(is_active=True)
    elif active_filter == 'false':
        qs = qs.filter(is_active=False)

    qs = qs.order_by('-date_joined')

    paginator = Paginator(qs, 25)
    page_number = request.GET.get('page', 1)
    page_obj = paginator.get_page(page_number)

    context = {
        'page_obj': page_obj,
        'search': search,
        'role_filter': role_filter,
        'active_filter': active_filter,
        'role_choices': User.Role.choices,
    }
    return render(request, 'admin_dashboard/users/list.html', context)


@admin_required
def user_detail(request, pk):
    """User detail page with activate/deactivate toggle."""
    user = get_object_or_404(User, pk=pk)
    profile = None
    profile_type = None

    if user.role == User.Role.ARTISAN:
        try:
            profile = user.artisanprofile
            profile_type = 'artisan'
        except ArtisanProfile.DoesNotExist:
            pass
    elif user.role == User.Role.CUSTOMER:
        try:
            profile = user.customerprofile
            profile_type = 'customer'
        except CustomerProfile.DoesNotExist:
            pass

    # Get user's jobs
    if user.role == User.Role.CUSTOMER:
        jobs = Job.objects.filter(customer=user).select_related('artisan__user').order_by('-created_at')[:10]
    elif user.role == User.Role.ARTISAN:
        try:
            jobs = Job.objects.filter(artisan=user.artisanprofile).select_related('customer').order_by('-created_at')[:10]
        except ArtisanProfile.DoesNotExist:
            jobs = []
    else:
        jobs = []

    context = {
        'user_obj': user,
        'profile': profile,
        'profile_type': profile_type,
        'jobs': jobs,
    }
    return render(request, 'admin_dashboard/users/detail.html', context)


@admin_required
@require_POST
def user_toggle_active(request, pk):
    """HTMX endpoint to toggle user active status."""
    user = get_object_or_404(User, pk=pk)
    user.is_active = not user.is_active
    user.save(update_fields=['is_active'])

    status = 'activated' if user.is_active else 'deactivated'
    logger.info("User %s (pk=%s) %s by admin %s", user.username, user.pk, status, request.user.username)
    messages.success(request, f'{user.username} has been {status}.')

    if request.headers.get('HX-Request'):
        return render(request, 'admin_dashboard/users/_toggle_active_btn.html', {'user_obj': user})

    return redirect('admin_dashboard:user_detail', pk=pk)


# ========================
# Artisan Management
# ========================

@admin_required
def artisan_list(request):
    """Paginated list of artisans with search and filters."""
    search = request.GET.get('search', '')
    verified_filter = request.GET.get('verified', '')
    available_filter = request.GET.get('available', '')

    qs = ArtisanProfile.objects.select_related('user').all()

    if search:
        qs = qs.filter(
            Q(profession__icontains=search) |
            Q(location__icontains=search) |
            Q(user__username__icontains=search)
        )
    if verified_filter == 'true':
        qs = qs.filter(is_verified=True)
    elif verified_filter == 'false':
        qs = qs.filter(is_verified=False)
    if available_filter:
        qs = qs.filter(is_available=available_filter)

    qs = qs.order_by('-user__date_joined')

    paginator = Paginator(qs, 25)
    page_number = request.GET.get('page', 1)
    page_obj = paginator.get_page(page_number)

    context = {
        'page_obj': page_obj,
        'search': search,
        'verified_filter': verified_filter,
        'available_filter': available_filter,
        'availability_statuses': ArtisanProfile.AvailabilityStatus.choices,
    }
    return render(request, 'admin_dashboard/artisans/list.html', context)


@admin_required
def artisan_detail(request, pk):
    """Artisan detail page with verify/unverify toggle."""
    profile = get_object_or_404(ArtisanProfile, pk=pk)
    jobs = Job.objects.filter(artisan=profile).select_related('customer').order_by('-created_at')[:10]
    review_count = Job.objects.filter(artisan=profile, status=Job.Status.COMPLETED, rating__isnull=False).count()

    # Get subscription info
    try:
        subscription = profile.subscription
    except Subscription.DoesNotExist:
        subscription = None

    context = {
        'profile': profile,
        'jobs': jobs,
        'review_count': review_count,
        'subscription': subscription,
    }
    return render(request, 'admin_dashboard/artisans/detail.html', context)


@admin_required
@require_POST
def artisan_toggle_verified(request, pk):
    """HTMX endpoint to toggle artisan verified status."""
    profile = get_object_or_404(ArtisanProfile, pk=pk)
    profile.is_verified = not profile.is_verified
    profile.save(update_fields=['is_verified'])

    status = 'verified' if profile.is_verified else 'unverified'
    messages.success(request, f'{profile.user.username} has been {status}.')

    if request.headers.get('HX-Request'):
        return render(request, 'admin_dashboard/artisans/_toggle_verified_btn.html', {'profile': profile})

    return redirect('admin_dashboard:artisan_detail', pk=pk)


# ========================
# Job Management
# ========================

@admin_required
def job_list(request):
    """Paginated list of all jobs with status filter."""
    status_filter = request.GET.get('status', '')
    search = request.GET.get('search', '')

    qs = Job.objects.select_related('customer', 'artisan__user', 'admin_approved_by').all()

    if status_filter:
        qs = qs.filter(status=status_filter)
    if search:
        qs = qs.filter(
            Q(description__icontains=search) |
            Q(location__icontains=search) |
            Q(customer__username__icontains=search)
        )

    qs = qs.order_by('-created_at')

    paginator = Paginator(qs, 25)
    page_number = request.GET.get('page', 1)
    page_obj = paginator.get_page(page_number)

    context = {
        'page_obj': page_obj,
        'status_filter': status_filter,
        'search': search,
        'status_choices': Job.Status.choices,
    }
    return render(request, 'admin_dashboard/jobs/list.html', context)


@admin_required
def job_detail(request, pk):
    """Job detail page with approve/reject actions."""
    job = get_object_or_404(Job, pk=pk)
    context = {'job': job}
    return render(request, 'admin_dashboard/jobs/detail.html', context)


@admin_required
@require_POST
def job_approve(request, pk):
    """Approve a pending job."""
    with db_transaction.atomic():
        job = Job.objects.select_for_update().get(pk=pk)
        if job.status != Job.Status.PENDING:
            messages.error(request, 'Only PENDING jobs can be approved.')
            return redirect('admin_dashboard:job_detail', pk=pk)
        job.status = Job.Status.ADMIN_APPROVED
        job.admin_approved_by = request.user
        job.admin_approved_at = timezone.now()
        job.save(update_fields=['status', 'admin_approved_by', 'admin_approved_at', 'updated_at'])

    messages.success(request, f'Job #{job.id} has been approved.')
    return redirect('admin_dashboard:job_detail', pk=pk)


@admin_required
@require_POST
def job_reject(request, pk):
    """Reject a pending job."""
    with db_transaction.atomic():
        job = Job.objects.select_for_update().get(pk=pk)
        if job.status != Job.Status.PENDING:
            messages.error(request, 'Only PENDING jobs can be rejected.')
            return redirect('admin_dashboard:job_detail', pk=pk)
        job.status = Job.Status.REJECTED
        job.save(update_fields=['status', 'updated_at'])

    messages.success(request, f'Job #{job.id} has been rejected.')
    return redirect('admin_dashboard:job_detail', pk=pk)


# ========================
# Dispute Management
# ========================

@admin_required
def dispute_list(request):
    """List all disputes with status filter."""
    status_filter = request.GET.get('status', '')

    qs = Dispute.objects.select_related('job__customer', 'job__artisan__user', 'resolved_by').all()

    if status_filter:
        qs = qs.filter(status=status_filter)

    qs = qs.order_by('-created_at')

    paginator = Paginator(qs, 25)
    page_number = request.GET.get('page', 1)
    page_obj = paginator.get_page(page_number)

    context = {
        'page_obj': page_obj,
        'status_filter': status_filter,
        'status_choices': Dispute.Status.choices,
    }
    return render(request, 'admin_dashboard/disputes/list.html', context)


@admin_required
def dispute_detail(request, pk):
    """Dispute detail page with resolution form."""
    dispute = get_object_or_404(Dispute, pk=pk)
    job = dispute.job

    context = {
        'dispute': dispute,
        'job': job,
        'form': DisputeResolveForm(),
    }
    return render(request, 'admin_dashboard/disputes/detail.html', context)


@admin_required
@require_POST
def dispute_resolve(request, pk):
    """Resolve a dispute."""
    dispute = get_object_or_404(Dispute, pk=pk)
    form = DisputeResolveForm(request.POST)

    if not form.is_valid():
        messages.error(request, 'Please fill in the resolution details.')
        return redirect('admin_dashboard:dispute_detail', pk=pk)

    resolution = form.cleaned_data['resolution']

    with db_transaction.atomic():
        dispute = Dispute.objects.select_for_update().get(pk=pk)
        dispute.resolution = resolution
        dispute.resolved_by = request.user
        dispute.resolved_at = timezone.now()

        dispute.status = Dispute.Status.RESOLVED
        dispute.save()

        job = dispute.job
        job.status = Job.Status.DISPUTED
        job.save(update_fields=['status', 'updated_at'])

    messages.success(request, 'Dispute resolved successfully.')
    logger.info("Dispute %s resolved by admin %s", dispute.pk, request.user.username)
    return redirect('admin_dashboard:dispute_detail', pk=pk)


# ========================
# Chat Management
# ========================

@admin_required
def conversation_list(request):
    """List all conversations."""
    qs = Conversation.objects.select_related('client', 'artisan', 'admin').all()
    qs = qs.order_by('-created_at')

    paginator = Paginator(qs, 25)
    page_number = request.GET.get('page', 1)
    page_obj = paginator.get_page(page_number)

    # Annotate with unread counts
    for conv in page_obj:
        conv.unread_count = conv.messages.filter(is_read=False).exclude(sender=request.user).count()

    context = {'page_obj': page_obj}
    return render(request, 'admin_dashboard/chats/list.html', context)


@admin_required
def conversation_detail(request, pk):
    """View conversation messages and send admin messages."""
    conversation = get_object_or_404(Conversation, pk=pk)
    messages_list = conversation.messages.select_related('sender').order_by('timestamp')

    # Mark unread messages as read
    Chat.objects.filter(
        conversation=conversation, is_read=False
    ).exclude(sender=request.user).update(is_read=True)

    # If admin isn't assigned yet, assign them
    if conversation.admin is None:
        conversation.admin = request.user
        conversation.save(update_fields=['admin'])

    form = ChatMessageForm()

    context = {
        'conversation': conversation,
        'messages_list': messages_list,
        'form': form,
    }
    return render(request, 'admin_dashboard/chats/detail.html', context)


@admin_required
@require_POST
def admin_send_message(request, conversation_id):
    """Send an admin message in a conversation."""
    conversation = get_object_or_404(Conversation, pk=conversation_id)
    form = ChatMessageForm(request.POST)

    if form.is_valid():
        text = form.cleaned_data['message'].strip()
        if text:
            Chat.objects.create(
                sender=request.user,
                conversation=conversation,
                message=text,
                is_admin_message=True,
                message_type='text',
            )

    if request.headers.get('HX-Request'):
        latest = Chat.objects.filter(conversation=conversation).order_by('-timestamp').first()
        return render(request, 'admin_dashboard/chats/_message.html', {'msg': latest})

    return redirect('admin_dashboard:conversation_detail', pk=conversation_id)


# ========================
# User Edit & Delete Views
# ========================

@admin_required
def user_edit(request, pk):
    """Edit user account and related profile fields."""
    user = get_object_or_404(User, pk=pk)
    profile = None
    profile_type = None

    if user.role == User.Role.ARTISAN:
        try:
            profile = user.artisanprofile
            profile_type = 'artisan'
        except ArtisanProfile.DoesNotExist:
            pass
    elif user.role == User.Role.CUSTOMER:
        try:
            profile = user.customerprofile
            profile_type = 'customer'
        except CustomerProfile.DoesNotExist:
            pass

    if request.method == 'POST':
        user_form = UserEditForm(request.POST, instance=user)
        profile_form = None

        if profile_type == 'customer' and profile:
            profile_form = CustomerProfileEditForm(request.POST, request.FILES, instance=profile)
        elif profile_type == 'artisan' and profile:
            profile_form = ArtisanProfileEditForm(request.POST, request.FILES, instance=profile)

        if user_form.is_valid() and (profile_form is None or profile_form.is_valid()):
            with db_transaction.atomic():
                user_form.save()
                if profile_form:
                    profile_form.save()
            messages.success(request, f'{user.username} has been updated.')
            return redirect('admin_dashboard:user_detail', pk=pk)
    else:
        user_form = UserEditForm(instance=user)
        profile_form = None
        if profile_type == 'customer' and profile:
            profile_form = CustomerProfileEditForm(instance=profile)
        elif profile_type == 'artisan' and profile:
            profile_form = ArtisanProfileEditForm(instance=profile)

    context = {
        'user_obj': user,
        'user_form': user_form,
        'profile_form': profile_form,
        'profile_type': profile_type,
    }
    return render(request, 'admin_dashboard/users/edit.html', context)


@admin_required
def user_delete(request, pk):
    """Delete confirmation page for a user (deactivate or permanent delete)."""
    user = get_object_or_404(User, pk=pk)

    # Prevent admin from deleting themselves
    if user.pk == request.user.pk:
        messages.error(request, 'You cannot delete your own account.')
        return redirect('admin_dashboard:user_detail', pk=pk)

    # Gather related data counts for display
    related_counts = {
        'jobs_as_customer': Job.objects.filter(customer=user).count(),
        'jobs_as_artisan': Job.objects.filter(artisan__user=user).count() if user.role == User.Role.ARTISAN else 0,
        'conversations': Conversation.objects.filter(Q(client=user) | Q(artisan=user)).count(),
        'reviews': Review.objects.filter(customer=user).count() if user.role == User.Role.CUSTOMER else (
            Review.objects.filter(artisan__user=user).count() if user.role == User.Role.ARTISAN else 0
        ),
    }
    # Include orphaned table counts (apps removed from codebase but tables still in DB)
    orphaned_tables = {
        'wallet': 'payments_wallet',
        'bank_account': 'payments_bankaccount',
    }
    with connection.cursor() as cursor:
        for label, table in orphaned_tables.items():
            try:
                cursor.execute(f"SELECT COUNT(*) FROM {table} WHERE user_id = %s", [user.pk])
                count = cursor.fetchone()[0]
                if count:
                    related_counts[label] = count
            except Exception:
                # Table may have been dropped; skip silently
                pass

    if request.method == 'POST':
        action = request.POST.get('action')

        if action == 'deactivate':
            user.is_active = False
            user.save(update_fields=['is_active'])
            messages.success(request, f'{user.username} has been deactivated.')
            logger.info("User %s (pk=%s) deactivated by admin %s", user.username, user.pk, request.user.username)
            return redirect('admin_dashboard:user_list')

        elif action == 'hard_delete':
            confirm_form = UserDeleteConfirmForm(request.POST)
            if confirm_form.is_valid() and confirm_form.cleaned_data['confirm_username'] == user.username:
                username = user.username
                with db_transaction.atomic():
                    user.delete()
                messages.success(request, f'User {username} has been permanently deleted.')
                logger.info("User %s (pk=%s) permanently deleted by admin %s", username, pk, request.user.username)
                return redirect('admin_dashboard:user_list')
            else:
                messages.error(request, 'Username confirmation does not match. User was not deleted.')
                return redirect('admin_dashboard:user_delete', pk=pk)

    context = {
        'user_obj': user,
        'related_counts': related_counts,
        'confirm_form': UserDeleteConfirmForm(),
    }
    return render(request, 'admin_dashboard/users/delete.html', context)


# ========================
# Artisan Edit & Delete Views
# ========================

@admin_required
def artisan_edit(request, pk):
    """Edit artisan profile and user account fields."""
    profile = get_object_or_404(ArtisanProfile, pk=pk)
    user = profile.user

    if request.method == 'POST':
        user_form = UserEditForm(request.POST, instance=user)
        profile_form = ArtisanProfileEditForm(request.POST, request.FILES, instance=profile)

        if user_form.is_valid() and profile_form.is_valid():
            with db_transaction.atomic():
                user_form.save()
                profile_form.save()
            messages.success(request, f'{user.username} has been updated.')
            return redirect('admin_dashboard:artisan_detail', pk=pk)
    else:
        user_form = UserEditForm(instance=user)
        profile_form = ArtisanProfileEditForm(instance=profile)

    context = {
        'profile': profile,
        'user_form': user_form,
        'profile_form': profile_form,
    }
    return render(request, 'admin_dashboard/artisans/edit.html', context)


@admin_required
def artisan_delete(request, pk):
    """Delete confirmation page for an artisan (deactivate or permanent delete)."""
    profile = get_object_or_404(ArtisanProfile, pk=pk)
    user = profile.user

    # Prevent admin from deleting themselves
    if user.pk == request.user.pk:
        messages.error(request, 'You cannot delete your own account.')
        return redirect('admin_dashboard:artisan_detail', pk=pk)

    # Gather related data counts for display
    related_counts = {
        'jobs_as_artisan': Job.objects.filter(artisan=profile).count(),
        'conversations': Conversation.objects.filter(artisan=user).count(),
        'reviews': Review.objects.filter(artisan=profile).count(),
    }
    # Include orphaned table counts (apps removed from codebase but tables still in DB)
    orphaned_tables = {
        'wallet': 'payments_wallet',
        'bank_account': 'payments_bankaccount',
    }
    with connection.cursor() as cursor:
        for label, table in orphaned_tables.items():
            try:
                cursor.execute(f"SELECT COUNT(*) FROM {table} WHERE user_id = %s", [user.pk])
                count = cursor.fetchone()[0]
                if count:
                    related_counts[label] = count
            except Exception:
                # Table may have been dropped; skip silently
                pass

    if request.method == 'POST':
        action = request.POST.get('action')

        if action == 'deactivate':
            user.is_active = False
            user.save(update_fields=['is_active'])
            messages.success(request, f'{user.username} has been deactivated.')
            logger.info("Artisan user %s (pk=%s) deactivated by admin %s", user.username, user.pk, request.user.username)
            return redirect('admin_dashboard:artisan_list')

        elif action == 'hard_delete':
            confirm_form = UserDeleteConfirmForm(request.POST)
            if confirm_form.is_valid() and confirm_form.cleaned_data['confirm_username'] == user.username:
                username = user.username
                with db_transaction.atomic():
                    user.delete()
                messages.success(request, f'Artisan {username} has been permanently deleted.')
                logger.info("Artisan user %s permanently deleted by admin %s", username, request.user.username)
                return redirect('admin_dashboard:artisan_list')
            else:
                messages.error(request, 'Username confirmation does not match. Artisan was not deleted.')
                return redirect('admin_dashboard:artisan_delete', pk=pk)

    context = {
        'profile': profile,
        'user_obj': user,
        'related_counts': related_counts,
        'confirm_form': UserDeleteConfirmForm(),
    }
    return render(request, 'admin_dashboard/artisans/delete.html', context)


# ========================
# Subscription Management
# ========================

@admin_required
def subscription_list(request):
    """List all subscriptions with search and filters."""
    search = request.GET.get('search', '')
    tier_filter = request.GET.get('tier', '')
    status_filter = request.GET.get('status', '')

    qs = Subscription.objects.select_related('artisan__user', 'activated_by').all()

    if search:
        qs = qs.filter(Q(artisan__user__username__icontains=search))
    if tier_filter:
        qs = qs.filter(tier=tier_filter)
    if status_filter == 'active':
        qs = qs.filter(
            Q(expires_at__isnull=True) | Q(expires_at__gt=timezone.now())
        ).exclude(tier=Subscription.Tier.FREE)
    elif status_filter == 'expired':
        qs = qs.filter(expires_at__lt=timezone.now()).exclude(tier=Subscription.Tier.FREE)
    elif status_filter == 'free':
        qs = qs.filter(tier=Subscription.Tier.FREE)

    qs = qs.order_by('-updated_at')

    paginator = Paginator(qs, 25)
    page_number = request.GET.get('page', 1)
    page_obj = paginator.get_page(page_number)

    # Also get artisans with no subscription (FREE tier by default)
    free_artisans_count = ArtisanProfile.objects.filter(subscription__isnull=True).count()

    context = {
        'page_obj': page_obj,
        'search': search,
        'tier_filter': tier_filter,
        'status_filter': status_filter,
        'tier_choices': Subscription.Tier.choices,
        'free_artisans_count': free_artisans_count,
    }
    return render(request, 'admin_dashboard/subscriptions/list.html', context)


@admin_required
def subscription_create(request):
    """Create a new subscription for an artisan."""
    artisan_id = request.GET.get('artisan_id', '')

    # Get artisans without a subscription (FREE by default)
    free_artisans = ArtisanProfile.objects.filter(
        subscription__isnull=True, user__is_active=True
    ).select_related('user').order_by('user__username')

    if request.method == 'POST':
        form = SubscriptionActivateForm(request.POST)
        if form.is_valid():
            artisan_pk = request.POST.get('artisan_id')
            try:
                artisan = ArtisanProfile.objects.get(pk=artisan_pk)
            except (ArtisanProfile.DoesNotExist, ValueError, TypeError):
                messages.error(request, 'Artisan not found.')
                return redirect('admin_dashboard:subscription_list')

            if Subscription.objects.filter(artisan=artisan).exists():
                messages.error(request, f'{artisan.user.username} already has a subscription. Use the activate page to change their tier.')
                return redirect('admin_dashboard:subscription_list')

            subscription = Subscription.objects.create(
                artisan=artisan,
                tier=form.cleaned_data['tier'],
                expires_at=timezone.now() + timedelta(days=form.cleaned_data['duration_days']),
                activated_by=request.user,
                notes=form.cleaned_data.get('notes', ''),
            )
            messages.success(request, f'{artisan.user.username} upgraded to {subscription.get_tier_display()}.')
            logger.info("Subscription created for %s (tier=%s) by admin %s",
                        artisan.user.username, subscription.tier, request.user.username)
            return redirect('admin_dashboard:subscription_list')
    else:
        form = SubscriptionActivateForm()

    context = {
        'form': form,
        'artisan_id': artisan_id,
        'free_artisans': free_artisans,
        'is_create': True,
    }
    return render(request, 'admin_dashboard/subscriptions/activate.html', context)


@admin_required
def subscription_activate(request, pk):
    """Activate or change a subscription tier."""
    subscription = get_object_or_404(Subscription, pk=pk)

    if request.method == 'POST':
        form = SubscriptionActivateForm(request.POST)
        if form.is_valid():
            subscription.tier = form.cleaned_data['tier']
            subscription.expires_at = timezone.now() + timedelta(days=form.cleaned_data['duration_days'])
            subscription.activated_by = request.user
            subscription.notes = form.cleaned_data.get('notes', '') or subscription.notes
            subscription.save()
            messages.success(request, f'{subscription.artisan.user.username} upgraded to {subscription.get_tier_display()}.')
            logger.info("Subscription %s activated (tier=%s) by admin %s",
                        subscription.pk, subscription.tier, request.user.username)
            return redirect('admin_dashboard:subscription_list')
    else:
        form = SubscriptionActivateForm()

    context = {
        'subscription': subscription,
        'form': form,
        'is_create': False,
    }
    return render(request, 'admin_dashboard/subscriptions/activate.html', context)


@admin_required
def subscription_deactivate(request, pk):
    """Revert subscription to FREE."""
    subscription = get_object_or_404(Subscription, pk=pk)

    if request.method == 'POST':
        subscription.tier = Subscription.Tier.FREE
        subscription.expires_at = None
        subscription.activated_by = request.user
        subscription.save()
        messages.success(request, f'{subscription.artisan.user.username} subscription reverted to Free.')
        logger.info("Subscription %s deactivated by admin %s", subscription.pk, request.user.username)
        return redirect('admin_dashboard:subscription_list')

    context = {'subscription': subscription}
    return render(request, 'admin_dashboard/subscriptions/deactivate.html', context)


