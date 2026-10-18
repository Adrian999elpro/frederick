import test from 'node:test';
import assert from 'node:assert/strict';
import { createPasswordRecovery } from '../web/js/password-recovery.js';

const redirectTo = 'https://adrian999elpro.github.io/frederick/index.html?view=reset';
function setup(overrides = {}) {
  const calls = [];
  let clock = 0;
  const auth = {
    async resetPasswordForEmail(...args) { calls.push(['request', ...args]); return { error: null }; },
    async verifyOtp(args) { calls.push(['verify', args]); return { data: { session: { access_token: 'test-session' } }, error: null }; },
    async updateUser(args) { calls.push(['update', args]); return { error: null }; },
    async signOut(args) { calls.push(['signOut', args]); return { error: null }; },
    ...overrides,
  };
  return { flow: createPasswordRecovery({ auth, redirectTo, now: () => clock }), calls, advance: (ms) => { clock += ms; } };
}

test('rechaza cambiar la contraseña sin verificar, aunque el formulario se abra directamente', async () => {
  const { flow, calls } = setup();
  await assert.rejects(flow.changePassword('A-secure-password', 'A-secure-password'), /Primero verifica/);
  assert.equal(calls.length, 0);
});
test('envía al correo normalizado y limita los reenvíos sin crear usuarios', async () => {
  const { flow, calls, advance } = setup();
  assert.equal(await flow.requestCode(' Alumno@Gmail.com '), 'alumno@gmail.com');
  assert.deepEqual(calls[0], ['request', 'alumno@gmail.com', { redirectTo }]);
  await assert.rejects(flow.requestCode('otro@gmail.com'), /Espera/);
  assert.equal(calls.length, 1);
  advance(60_000);
  await flow.requestCode('alumno@gmail.com');
  assert.equal(calls.length, 2);
});
test('un fallo de envío no se presenta como éxito y no revela si existe la cuenta', async () => {
  const { flow } = setup({ async resetPasswordForEmail() { return { error: { status: 500, message: 'account-does-not-exist' } }; } });
  await assert.rejects(flow.requestCode('alumno@gmail.com'), (e) => e.message.includes('No pudimos enviar') && !e.message.includes('account-does-not-exist'));
});
test('los códigos inválidos o caducados no habilitan el cambio de contraseña', async () => {
  const { flow, calls } = setup({ async verifyOtp() { return { data: null, error: { message: 'otp_expired' } }; } });
  await assert.rejects(flow.verifyCode('alumno@gmail.com', '123456'), /caducó/);
  await assert.rejects(flow.changePassword('A-secure-password', 'A-secure-password'), /Primero verifica/);
  assert.equal(calls.length, 0);
});
test('verifica con el tipo recovery, exige contraseñas iguales y cierra la sesión tras guardar', async () => {
  const { flow, calls } = setup();
  await flow.verifyCode(' Alumno@gmail.com ', '123 456');
  assert.deepEqual(calls[0], ['verify', { email: 'alumno@gmail.com', token: '123456', type: 'recovery' }]);
  await assert.rejects(flow.changePassword('A-secure-password', 'another-password'), /no coinciden/);
  await flow.changePassword('A-secure-password', 'A-secure-password');
  assert.deepEqual(calls.slice(1), [['update', { password: 'A-secure-password' }], ['signOut', { scope: 'local' }]]);
  await assert.rejects(flow.changePassword('A-secure-password', 'A-secure-password'), /Primero verifica/);
});
test('no acepta una respuesta de verificación sin sesión', async () => {
  const { flow } = setup({ async verifyOtp() { return { data: { session: null }, error: null }; } });
  await assert.rejects(flow.verifyCode('alumno@gmail.com', '123456'), /no es válido/);
});
