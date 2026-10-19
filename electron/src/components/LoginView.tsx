import React from 'react';
import {
  Button,
  Column,
  Content,
  Spinner,
  Window,
  WindowMain,
} from '../macos/macos';

export interface LoginViewProps {
  restoring: boolean;
  signingIn: boolean;
  error: string | null;
  onSignIn: () => void;
  onSignInOffline: () => void;
}

export function LoginView({
  restoring,
  signingIn,
  error,
  onSignIn,
  onSignInOffline,
}: LoginViewProps) {
  return (
    <Window style={{ width: '100vw', height: '100vh', borderRadius: 0 }}>
      <WindowMain>
        <Content>
          <div
            style={{
              height: '100%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <Column
              style={{
                maxWidth: 340,
                textAlign: 'center',
                alignItems: 'center',
                gap: 14,
              }}
            >
              <img
                src="./assets/logo/mario_mark.png"
                alt="Mario"
                style={{ width: 64, height: 64, borderRadius: 14 }}
              />
              <div>
                <h1 className="mac-title-1" style={{ margin: '0 0 6px 0' }}>
                  Mario
                </h1>
                <p className="mac-label-secondary" style={{ margin: 0 }}>
                  Your notebooks, sections, and pages — synced across devices
                  with Google Drive and local AI.
                </p>
              </div>
              {restoring ? (
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 8,
                    marginTop: 8,
                  }}
                >
                  <Spinner label="Restoring session" />
                  <span className="mac-label-secondary">
                    Restoring your session…
                  </span>
                </div>
              ) : (
                <>
                  <Button
                    variant="prominent"
                    size="large"
                    disabled={signingIn}
                    onClick={onSignIn}
                    style={{ width: '100%', minWidth: 220 }}
                  >
                    {signingIn ? 'Signing in…' : 'Continue with Google'}
                  </Button>
                  <Button
                    variant="bordered"
                    size="large"
                    disabled={signingIn}
                    onClick={onSignInOffline}
                    style={{ width: '100%', minWidth: 220 }}
                  >
                    Continue Offline
                  </Button>
                  {error && (
                    <p
                      className="mac-footnote mac-label-red"
                      style={{ margin: 0 }}
                    >
                      {error}
                    </p>
                  )}
                </>
              )}
            </Column>
          </div>
        </Content>
      </WindowMain>
    </Window>
  );
}
