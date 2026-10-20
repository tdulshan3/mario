import React from 'react';
import { Button, EmptyState } from '../macos/macos';

/**
 * Keeps an error in one part of the window (the AI panel, the page's Ask box)
 * from taking the whole window down: React unmounts everything above an
 * uncaught render error. Shows what failed and a way to try again.
 */
export class ErrorBoundary extends React.Component<
  {
    title: string;
    children: React.ReactNode;
    compact?: boolean;
    /** A change (another notebook, say) clears a caught error and tries again. */
    resetKey?: string;
  },
  { error: Error | null }
> {
  state: { error: Error | null } = { error: null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  componentDidUpdate(prev: { resetKey?: string }) {
    if (this.state.error && prev.resetKey !== this.props.resetKey) this.setState({ error: null });
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error(`[${this.props.title}]`, error, info.componentStack);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    const retry = (
      <Button size="small" onClick={() => this.setState({ error: null })}>
        Try Again
      </Button>
    );
    if (this.props.compact) {
      return (
        <div className="mario-error-note" role="alert">
          <span className="mac-footnote mac-label-red">
            {this.props.title}: {error.message}
          </span>
          {retry}
        </div>
      );
    }
    return (
      <div className="mario-error-pane" role="alert">
        <EmptyState icon="exclamationmark-triangle" title={this.props.title} message={error.message} actions={retry} />
      </div>
    );
  }
}
