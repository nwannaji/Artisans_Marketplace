from django import forms

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

