// Тонкая обёртка над fetch: JSON, ошибки текстом, 409 — отдельный класс.
export class ApiError extends Error {
  constructor(public status: number, message: string, public data?: any) {
    super(message);
  }
}
export class Conflict extends ApiError {
  constructor(public current: any) {
    super(409, 'Кто-то уже изменил эту запись', current);
  }
}

async function call<T = any>(method: string, url: string, body?: unknown, raw?: FormData): Promise<T> {
  const res = await fetch('/api' + url, {
    method,
    headers: raw ? undefined : body !== undefined ? { 'content-type': 'application/json' } : undefined,
    body: raw ?? (body !== undefined ? JSON.stringify(body) : undefined),
    credentials: 'same-origin',
  });
  const text = await res.text();
  let data: any = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { error: text };
  }
  if (res.status === 409) throw new Conflict(data?.current);
  if (!res.ok) throw new ApiError(res.status, data?.error ?? res.statusText, data);
  return data as T;
}

export const api = {
  get: <T = any>(url: string) => call<T>('GET', url),
  post: <T = any>(url: string, body?: unknown) => call<T>('POST', url, body),
  put: <T = any>(url: string, body?: unknown) => call<T>('PUT', url, body),
  patch: <T = any>(url: string, body?: unknown) => call<T>('PATCH', url, body),
  del: <T = any>(url: string) => call<T>('DELETE', url),
  upload: <T = any>(url: string, form: FormData) => call<T>('POST', url, undefined, form),
};

export const mediaUrl = (season: string, id: string) => `/media/${season}/${id}`;
