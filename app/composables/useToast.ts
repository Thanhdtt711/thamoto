export interface ToastState {
  visible: boolean;
  message: string;
  type: 'success' | 'error';
}

let timer: ReturnType<typeof setTimeout> | null = null;

export function useToast() {
  const toast = useState<ToastState>('app-toast', () => ({
    visible: false,
    message: '',
    type: 'success'
  }));

  const showToast = (message: string, type: 'success' | 'error' = 'success', duration = 3200) => {
    if (timer) clearTimeout(timer);
    toast.value = { visible: true, message, type };
    if (import.meta.client) {
      timer = setTimeout(() => {
        toast.value.visible = false;
      }, duration);
    }
  };

  return { toast, showToast };
}
