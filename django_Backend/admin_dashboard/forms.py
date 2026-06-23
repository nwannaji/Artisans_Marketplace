from django import forms
from decimal import Decimal

# Tailwind CSS utility classes for form widgets
INPUT_CLASS = 'w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-brand/30 focus:border-brand outline-none transition-colors'
TEXTAREA_CLASS = 'w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-brand/30 focus:border-brand outline-none transition-colors'
SELECT_CLASS = 'w-full px-3 py-2.5 border border-gray-300 rounded-lg text-sm bg-white focus:ring-2 focus:ring-brand/30 focus:border-brand outline-none transition-colors'
CHECKBOX_CLASS = 'rounded border-gray-300 text-brand focus:ring-brand'


class LoginForm(forms.Form):
    username = forms.CharField(
        max_length=150,
        widget=forms.TextInput(attrs={
            'class': INPUT_CLASS,
            'placeholder': 'Username',
            'autofocus': True,
        })
    )
    password = forms.CharField(
        widget=forms.PasswordInput(attrs={
            'class': INPUT_CLASS,
            'placeholder': 'Password',
        })
    )


class DisputeResolveForm(forms.Form):
    resolution = forms.CharField(
        widget=forms.Textarea(attrs={
            'class': TEXTAREA_CLASS,
            'rows': 3,
            'placeholder': 'Describe the resolution...',
        }),
        required=True,
    )
    refund_amount = forms.DecimalField(
        max_digits=10,
        decimal_places=2,
        required=False,
        widget=forms.NumberInput(attrs={
            'class': INPUT_CLASS,
            'placeholder': 'Leave blank for full refund',
            'step': '0.01',
        }),
    )
    full_refund = forms.BooleanField(
        required=False,
        widget=forms.CheckboxInput(attrs={'class': CHECKBOX_CLASS}),
    )


class CommissionSettingsForm(forms.Form):
    """Commission rate entered as a percentage (e.g., 10 for 10%).
    Internally stored as a decimal (0.10).
    """
    commission_rate = forms.DecimalField(
        max_digits=5,
        decimal_places=2,
        min_value=Decimal('0.00'),
        max_value=Decimal('100.00'),
        widget=forms.NumberInput(attrs={
            'class': INPUT_CLASS,
            'step': '0.01',
            'min': '0',
            'max': '100',
        }),
        help_text='Enter as percentage (e.g., 10 for 10%)',
    )

    def clean_commission_rate(self):
        value = self.cleaned_data['commission_rate']
        if value < 0 or value > 100:
            raise forms.ValidationError('Rate must be between 0 and 100.')
        return value


class ChatMessageForm(forms.Form):
    message = forms.CharField(
        max_length=2000,
        widget=forms.TextInput(attrs={
            'class': INPUT_CLASS,
            'placeholder': 'Type a message...',
            'autocomplete': 'off',
        }),
        required=True,
    )


class EscrowRefundForm(forms.Form):
    refund_amount = forms.DecimalField(
        max_digits=10,
        decimal_places=2,
        required=False,
        widget=forms.NumberInput(attrs={
            'class': INPUT_CLASS,
            'placeholder': 'Leave blank for full refund',
            'step': '0.01',
        }),
    )
    full_refund = forms.BooleanField(
        required=False,
        widget=forms.CheckboxInput(attrs={'class': CHECKBOX_CLASS}),
    )