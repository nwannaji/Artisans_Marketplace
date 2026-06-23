import logging

from django.contrib.auth import authenticate, login, logout
from django.contrib import messages
from django.db.models import Count, Sum, Q, Avg
from django.db import transaction as db_transaction
from django.shortcuts import get_object_or_404, redirect, render
from django.utils import timezone
from django.views.decorators.http import require_POST
from django.core.paginator import Paginator
from decimal import Decimal

from .decorators import admin_required
from .forms import (
    LoginForm, DisputeResolveForm, CommissionSettingsForm,
    ChatMessageForm, EscrowRefundForm,
)
from accounts.models import User, ArtisanProfile, CustomerProfile
from bookings.models import Job
from payments.models import Wallet, Transaction, AppSettings, BankAccount
from payments.utils import process_escrow_release, process_escrow_refund
from chats.models import Conversation, Chat
from disputes.models import Dispute

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

    total_escrow_held = Job.objects.filter(
        escrow_held_amount__gt=0
    ).aggregate(total=Sum('escrow_held_amount'))['total'] or Decimal('0')

    open_disputes = Dispute.objects.filter(
        status__in=[Dispute.Status.OPEN, Dispute.Status.IN_REVIEW]
    ).count()

    pending_deposits = Transaction.objects.filter(
        transaction_type=Transaction.Type.DEPOSIT,
        status=Transaction.Status.PENDING
    ).count()

    recent_jobs = Job.objects.select_related(
        'customer', 'artisan__user'
    ).order_by('-created_at')[:10]

    recent_disputes = Dispute.objects.select_related(
        'job__customer', 'job__artisan__user'
    ).order_by('-created_at')[:5]

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
        'total_escrow_held': total_escrow_held,
        'open_disputes': open_disputes,
        'pending_deposits': pending_deposits,
        'recent_jobs': recent_jobs,
        'recent_disputes': recent_disputes,
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

    # Get wallet
    wallet = None
    try:
        wallet = user.wallet
    except Wallet.DoesNotExist:
        pass

    context = {
        'user_obj': user,
        'profile': profile,
        'profile_type': profile_type,
        'jobs': jobs,
        'wallet': wallet,
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
    bank_accounts = BankAccount.objects.filter(user=profile.user).order_by('-is_default', '-created_at')
    wallet, _ = Wallet.objects.get_or_create(user=profile.user)

    context = {
        'profile': profile,
        'jobs': jobs,
        'review_count': review_count,
        'bank_accounts': bank_accounts,
        'wallet': wallet,
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
# Escrow Management
# ========================

@admin_required
def escrow_list(request):
    """List all jobs with held escrow."""
    qs = Job.objects.filter(
        escrow_held_amount__gt=0
    ).select_related('customer', 'artisan__user').order_by('-created_at')

    paginator = Paginator(qs, 25)
    page_number = request.GET.get('page', 1)
    page_obj = paginator.get_page(page_number)

    context = {'page_obj': page_obj}
    return render(request, 'admin_dashboard/escrow/list.html', context)


@admin_required
def escrow_detail(request, pk):
    """Escrow detail page with release/refund actions."""
    job = get_object_or_404(Job, pk=pk)
    transactions = Transaction.objects.filter(job=job).select_related('wallet__user').order_by('-created_at')

    context = {
        'job': job,
        'transactions': transactions,
    }
    return render(request, 'admin_dashboard/escrow/detail.html', context)


@admin_required
@require_POST
def escrow_release(request, pk):
    """Release escrow to artisan minus commission."""
    with db_transaction.atomic():
        job = Job.objects.select_for_update().get(pk=pk)
        if not job.escrow_held_amount or job.escrow_held_amount <= 0:
            messages.error(request, 'No escrow held for this job.')
            return redirect('admin_dashboard:escrow_detail', pk=pk)
        if not job.artisan:
            messages.error(request, 'No artisan assigned to this job.')
            return redirect('admin_dashboard:escrow_detail', pk=pk)
        if job.status not in [Job.Status.IN_PROGRESS, Job.Status.COMPLETED]:
            messages.error(request, 'Job must be IN_PROGRESS or COMPLETED to release escrow.')
            return redirect('admin_dashboard:escrow_detail', pk=pk)

        artisan_payout, commission_amount = process_escrow_release(job)
        if job.status != Job.Status.COMPLETED:
            job.status = Job.Status.COMPLETED
            job.save(update_fields=['status', 'updated_at'])

    messages.success(request, f'Escrow released. Artisan payout: ₦{artisan_payout}, Commission: ₦{commission_amount}')
    return redirect('admin_dashboard:escrow_detail', pk=pk)


@admin_required
@require_POST
def escrow_refund(request, pk):
    """Refund escrow to customer (full or partial).

    Validation is done inside the atomic block after acquiring the row lock
    to prevent TOCTOU issues.
    """
    form = EscrowRefundForm(request.POST)

    with db_transaction.atomic():
        job = Job.objects.select_for_update().get(pk=pk)

        if not job.escrow_held_amount or job.escrow_held_amount <= 0:
            messages.error(request, 'No escrow held for this job.')
            # Must redirect outside the atomic block — raise an exception
            # to trigger rollback, then redirect
            db_transaction.set_rollback(True)
            return redirect('admin_dashboard:escrow_detail', pk=pk)

        if form.is_valid() and form.cleaned_data.get('full_refund'):
            refund_amount = job.escrow_held_amount
        elif form.is_valid() and form.cleaned_data.get('refund_amount'):
            refund_amount = form.cleaned_data['refund_amount']
            if refund_amount > job.escrow_held_amount:
                messages.error(request, f'Refund amount cannot exceed ₦{job.escrow_held_amount}')
                db_transaction.set_rollback(True)
                return redirect('admin_dashboard:escrow_detail', pk=pk)
        else:
            refund_amount = job.escrow_held_amount  # Default: full refund

        process_escrow_refund(job, refund_amount)

    messages.success(request, f'₦{refund_amount} refunded to customer.')
    return redirect('admin_dashboard:escrow_detail', pk=pk)


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
    transactions = Transaction.objects.filter(job=job).select_related('wallet__user').order_by('-created_at')

    context = {
        'dispute': dispute,
        'job': job,
        'transactions': transactions,
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
    refund_amount = form.cleaned_data.get('refund_amount')
    full_refund = form.cleaned_data.get('full_refund')

    with db_transaction.atomic():
        dispute = Dispute.objects.select_for_update().get(pk=pk)
        dispute.resolution = resolution
        dispute.resolved_by = request.user
        dispute.resolved_at = timezone.now()

        job = dispute.job
        if full_refund and job.escrow_held_amount and job.escrow_held_amount > 0:
            process_escrow_refund(job, job.escrow_held_amount)
            refund_amount = job.escrow_held_amount
        elif refund_amount and job.escrow_held_amount and job.escrow_held_amount > 0:
            actual_refund = min(refund_amount, job.escrow_held_amount)
            process_escrow_refund(job, actual_refund)

        dispute.status = Dispute.Status.RESOLVED
        dispute.save()

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
# Settings
# ========================

@admin_required
def commission_settings(request):
    """View and update commission rate.

    The form accepts percentages (e.g., 10 for 10%) and converts
    to/from the decimal stored in AppSettings (e.g., 0.10).
    """
    current_rate_decimal = AppSettings.get_commission_rate()  # e.g. Decimal('0.10')
    current_rate_pct = current_rate_decimal * Decimal('100')    # e.g. Decimal('10.00')

    if request.method == 'POST':
        form = CommissionSettingsForm(request.POST)
        if form.is_valid():
            pct_value = form.cleaned_data['commission_rate']  # e.g. Decimal('10.00')
            decimal_value = pct_value / Decimal('100')       # e.g. Decimal('0.10')
            old_value = AppSettings.get_value('commission_rate')
            AppSettings.objects.update_or_create(
                key='commission_rate',
                defaults={'value': str(decimal_value)}
            )
            # Log the change
            AppSettings.objects.update_or_create(
                key=f'commission_rate_change_{timezone.now().strftime("%Y%m%d%H%M%S")}',
                defaults={'value': f'new={decimal_value};old={old_value};by={request.user.username}'}
            )
            messages.success(request, f'Commission rate updated to {float(pct_value):.1f}%')
            return redirect('admin_dashboard:commission_settings')
    else:
        form = CommissionSettingsForm(initial={'commission_rate': current_rate_pct})

    # Commission revenue stats
    total_commission = Transaction.objects.filter(
        transaction_type=Transaction.Type.COMMISSION,
        status=Transaction.Status.COMPLETED
    ).aggregate(total=Sum('amount'))['total'] or Decimal('0')

    completed_jobs = Job.objects.filter(status=Job.Status.COMPLETED).count()

    # Recent commission changes
    recent_changes = []
    for setting in AppSettings.objects.filter(
        key__startswith='commission_rate_change_'
    ).order_by('-pk')[:10]:
        # Parse: new=0.10;old=0.05;by=admin
        parts = {}
        for part in setting.value.split(';'):
            if '=' in part:
                k, v = part.split('=', 1)
                parts[k.strip()] = v.strip()
        recent_changes.append({
            'new_value': Decimal(parts.get('new', '0')) * Decimal('100'),
            'old_value': Decimal(parts.get('old', '0')) * Decimal('100') if parts.get('old') else None,
            'changed_by': type('U', (), {'username': parts.get('by', 'System')})(),
            'created_at': setting.pk  # Approximate — real date would need a created_at field
        })

    context = {
        'form': form,
        'current_rate': float(current_rate_pct),
        'total_commission': total_commission,
        'completed_jobs': completed_jobs,
        'recent_changes': recent_changes,
    }
    return render(request, 'admin_dashboard/settings/commission.html', context)


# ========================
# Transaction / Deposit Management
# ========================

@admin_required
def transaction_list(request):
    """List all transactions with filters."""
    status_filter = request.GET.get('status', '')
    type_filter = request.GET.get('type', '')
    search = request.GET.get('search', '')

    transactions = Transaction.objects.select_related(
        'wallet__user'
    ).order_by('-created_at')

    if status_filter:
        transactions = transactions.filter(status=status_filter)
    if type_filter:
        transactions = transactions.filter(transaction_type=type_filter)
    if search:
        transactions = transactions.filter(
            Q(reference__icontains=search) | Q(wallet__user__username__icontains=search)
        )

    paginator = Paginator(transactions, 25)
    page_number = request.GET.get('page', 1)
    page_obj = paginator.get_page(page_number)

    context = {
        'page_obj': page_obj,
        'status_filter': status_filter,
        'type_filter': type_filter,
        'search': search,
        'status_choices': Transaction.Status.choices,
        'type_choices': Transaction.Type.choices,
    }
    return render(request, 'admin_dashboard/transactions/list.html', context)


@admin_required
def transaction_complete(request, pk):
    """Admin manually completes a PENDING deposit — credits the wallet.

    This is for development/testing when Paystack callbacks are not available,
    or for manual approval in production.
    """
    transaction = get_object_or_404(Transaction, pk=pk)

    if transaction.status != Transaction.Status.PENDING:
        messages.error(request, f'Transaction is {transaction.get_status_display()}, not PENDING.')
        return redirect('admin_dashboard:transaction_list')

    if transaction.transaction_type != Transaction.Type.DEPOSIT:
        messages.error(request, 'Only DEPOSIT transactions can be manually completed from here.')
        return redirect('admin_dashboard:transaction_list')

    with db_transaction.atomic():
        wallet = Wallet.objects.select_for_update().get(pk=transaction.wallet.pk)
        wallet.balance += transaction.amount
        wallet.save(update_fields=['balance', 'updated_at'])
        transaction.status = Transaction.Status.COMPLETED
        transaction.save(update_fields=['status'])

    messages.success(
        request,
        f'Deposit of ₦{transaction.amount} completed for {transaction.wallet.user.username}. '
        f'New balance: ₦{wallet.balance}'
    )
    return redirect('admin_dashboard:transaction_list')


@admin_required
def transaction_fail(request, pk):
    """Admin marks a PENDING transaction as FAILED."""
    transaction = get_object_or_404(Transaction, pk=pk)

    if transaction.status != Transaction.Status.PENDING:
        messages.error(request, f'Transaction is {transaction.get_status_display()}, not PENDING.')
        return redirect('admin_dashboard:transaction_list')

    transaction.status = Transaction.Status.FAILED
    transaction.save(update_fields=['status'])

    messages.success(request, f'Transaction {transaction.reference} marked as FAILED.')
    return redirect('admin_dashboard:transaction_list')