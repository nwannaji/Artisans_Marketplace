import json

from django import forms
from accounts.models import User, ArtisanProfile, CustomerProfile

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


class UserEditForm(forms.ModelForm):
    """Admin form for editing user account fields."""

    class Meta:
        model = User
        fields = ['username', 'email', 'first_name', 'last_name',
                  'phone_number', 'role', 'is_verified', 'is_active']
        widgets = {
            'username': forms.TextInput(attrs={'class': INPUT_CLASS}),
            'email': forms.EmailInput(attrs={'class': INPUT_CLASS}),
            'first_name': forms.TextInput(attrs={'class': INPUT_CLASS}),
            'last_name': forms.TextInput(attrs={'class': INPUT_CLASS}),
            'phone_number': forms.TextInput(attrs={'class': INPUT_CLASS}),
            'role': forms.Select(attrs={'class': SELECT_CLASS}),
            'is_verified': forms.CheckboxInput(attrs={'class': CHECKBOX_CLASS}),
            'is_active': forms.CheckboxInput(attrs={'class': CHECKBOX_CLASS}),
        }

    def clean_role(self):
        role = self.cleaned_data.get('role')
        if self.instance and self.instance.pk:
            original_role = User.objects.get(pk=self.instance.pk).role
            if role != original_role and original_role in (User.Role.CUSTOMER, User.Role.ARTISAN):
                raise forms.ValidationError(
                    'Changing role between Customer and Artisan is not supported here. '
                    'Please create a new user with the desired role instead.'
                )
        return role


class CustomerProfileEditForm(forms.ModelForm):
    """Admin form for editing customer profile fields."""

    class Meta:
        model = CustomerProfile
        fields = ['address', 'bio', 'profile_picture']
        widgets = {
            'address': forms.Textarea(attrs={'class': TEXTAREA_CLASS, 'rows': 3}),
            'bio': forms.Textarea(attrs={'class': TEXTAREA_CLASS, 'rows': 3}),
            'profile_picture': forms.ClearableFileInput(attrs={'class': INPUT_CLASS}),
        }


class ArtisanProfileEditForm(forms.ModelForm):
    """Admin form for editing artisan profile fields."""

    class Meta:
        model = ArtisanProfile
        fields = ['profession', 'skills', 'hourly_rate', 'location',
                  'latitude', 'longitude', 'bio', 'is_available',
                  'is_verified', 'profile_picture']
        widgets = {
            'profession': forms.TextInput(attrs={'class': INPUT_CLASS}),
            'skills': forms.Textarea(attrs={
                'class': TEXTAREA_CLASS, 'rows': 3,
                'placeholder': 'Enter skills as JSON array, e.g. ["Plumbing", "Electrical"]',
            }),
            'hourly_rate': forms.NumberInput(attrs={'class': INPUT_CLASS, 'step': '0.01'}),
            'location': forms.TextInput(attrs={'class': INPUT_CLASS}),
            'latitude': forms.NumberInput(attrs={'class': INPUT_CLASS, 'step': '0.000001'}),
            'longitude': forms.NumberInput(attrs={'class': INPUT_CLASS, 'step': '0.000001'}),
            'bio': forms.Textarea(attrs={'class': TEXTAREA_CLASS, 'rows': 3}),
            'is_available': forms.Select(attrs={'class': SELECT_CLASS}),
            'is_verified': forms.CheckboxInput(attrs={'class': CHECKBOX_CLASS}),
            'profile_picture': forms.ClearableFileInput(attrs={'class': INPUT_CLASS}),
        }

    def clean_skills(self):
        value = self.cleaned_data.get('skills')
        if isinstance(value, list):
            if not all(isinstance(item, str) for item in value):
                raise forms.ValidationError('Skills must be a list of text values.')
            return value
        if isinstance(value, str):
            try:
                parsed = json.loads(value)
                if not isinstance(parsed, list):
                    raise forms.ValidationError('Skills must be a JSON array of strings.')
                if not all(isinstance(item, str) for item in parsed):
                    raise forms.ValidationError('Each skill must be a text value.')
                return parsed
            except json.JSONDecodeError:
                raise forms.ValidationError(
                    'Invalid JSON format. Enter a list like ["Plumbing", "Electrical"].'
                )
        return value


class UserDeleteConfirmForm(forms.Form):
    """Form requiring the admin to type the username to confirm permanent deletion."""
    confirm_username = forms.CharField(
        max_length=150,
        widget=forms.TextInput(attrs={
            'class': INPUT_CLASS,
            'placeholder': 'Type the username to confirm',
            'autocomplete': 'off',
        }),
        required=True,
    )

