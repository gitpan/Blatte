package Blatte;

use strict;
use base 'Exporter';
use vars qw($VERSION @EXPORT_OK);

use Blatte::Ws;

BEGIN {
  $VERSION = '0.9.1';
  @EXPORT_OK = qw(Parse traverse
                  flatten
                  wrapws unwrapws wsof
                  true quote);
}

my $parser;

sub Parse {
  my $input = shift;

  if (!defined($parser)) {
    use Blatte::Parser;
    $parser = new Blatte::Parser() unless defined($parser);
  }

  $parser->parse($input);
}

sub wrapws {
  my($ws, $obj) = @_;
  new Blatte::Ws($ws, $obj);
}

sub unwrapws {
  my $obj = shift;
  if (defined($obj) && UNIVERSAL::isa($obj, 'Blatte::Ws')) {
    return &unwrapws($obj->obj());
  }
  $obj;
}

sub wsof {
  my $obj = shift;
  if (defined($obj) && UNIVERSAL::isa($obj, 'Blatte::Ws')) {
    return $obj->ws();
  }
  '';
}

sub true {
  my $obj = &unwrapws(shift);

  if (defined($obj) && (ref($obj) eq 'ARRAY')) {
    @$obj && $obj;              # empty array counts as false
  } else {
    $obj;                       # else use Perl rules
  }
}

sub quote {
  my $str = shift;

  if ($str eq '') {
    $str = '\\"\\"';
  } elsif ($str =~ /\s/) {
    $str =~ s/\\/\\\\/g;
    $str = "\\\"$str\\\"";
  } else {
    $str =~ s/([\\{}])/\\$1/g;
  }
  $str;
}

sub traverse {
  my($obj, $cb, $ws) = @_;

  if (UNIVERSAL::isa($obj, 'Blatte::Ws')) {
    return &traverse($obj->obj(), $cb, (defined($ws) ? $ws : $obj->ws()));
  }

  if (ref($obj) eq 'ARRAY') {
    my $result;

    if (@$obj) {
      $result = &traverse($obj->[0], $cb, $ws);
      foreach my $subobj (@{$obj}[1 .. $#$obj]) {
        my $r2 = &traverse($subobj, $cb, ($result ? undef : $ws));
        $result ||= $r2;
      }
    }

    return $result;
  }

  return &$cb($ws, $obj);
}

sub flatten {
  my($obj, $inital_ws) = @_;

  my $result = '';

  &traverse($obj, sub {
    my($ws, $obj) = @_;
    $result .= $ws if defined($ws);
    $result .= $obj;
    return 1;
  }, $inital_ws);

  $result;
}

1;

__END__

=head1 NAME

Blatte - text macro/markup/template language

=head1 SYNOPSIS

  use Blatte;
  use Blatte::Builtins;

  my $perl = &Blatte::Parse('...some Blatte program ...');
  if (defined($perl)) {
    my $result = eval $perl;
    if (defined($result)) {
      &Blatte::traverse($result, \&callback);
    } elsif ($@) {
      ...handle execution error...
    }
  } else {
    ...handle parsing error...
  }

=head1 DESCRIPTION

Blatte is a very powerful text markup and transformation language with
a very simple syntax.  A Blatte document can be translated into a Perl
program that, when executed, produces a transformed version of the
input document.

This module itself contains some utility functions for handling Blatte
documents, described below in the FUNCTIONS section.  However, writers
of Blatte-based software will generally be more interested in other
associated modules.  See in particular L<Blatte::Compiler> (for
processing files full of Blatte code) and L<Blatte::Builtins> (for a
description of the Blatte language's intrinsic functions).

Most casual end users will probably be interested in Blatte's ability
to serve as a higher-level language for writing web pages.  This
requires the additional CPAN package Blatte::HTML.

Most of the remainder of this document describes the syntax and
semantics of the Blatte language.

=head1 THE BLATTE LANGUAGE

Blatte has three metacharacters: \ { }.  These are used to represent
lists, variables, syntactic forms, function calls, string literals,
comments, and a "forget-whitespace" operator explained below.

Everything else in a Blatte document is either whitespace or is
divided into "words," also explained below.

To include a literal metacharacter, precede it with backslash: \\, \{,
and \}.

All Blatte expressions correspond to equivalent Perl expressions.
When a Blatte document is parsed, its Blatte expressions are converted
to Perl, which may then be evaluated.

Here is a quick rundown of Blatte expression types.

=over 4

=item \VAR

This is a variable reference.  The identifier following the \ must
begin with a letter, and may be followed by letters, digits, or
underscore.

This corresponds to the Perl scalar variable $var.  All values in
Blatte are Perl scalars.

=item {\define \VAR EXPR}

This defines a new variable \VAR to contain the value of the Blatte
expression EXPR.

This corresponds to the Perl sequence

  use vars '$var';
  $var = EXPR;

(where EXPR has been transformed to its Perl equivalent).

=item {\set! \VAR EXPR}

This sets the existing variable \VAR to the value of the Blatte
expression EXPR.

This corresponds to the Perl expression

  $VAR = EXPR

=item {\if TEST THEN ELSE1 ELSE2 ...}

This evaluates TEST.  If the result is true, it evaluates and returns
THEN; otherwise it evaluates the ELSEs and returns the value of the
last one.

All Blatte values are true except for 0 and the empty string (as in
Perl) and the empty Blatte list, {} (which corresponds to the Perl
array reference []).

Perl equivalent:

  if (TEST) {
    THEN;
  } else {
    ELSE1;
    ELSE2;
    ...
  }

=item {\and EXPR1 EXPR2 ...}

Evaluates each EXPR in turn, stopping if one yields a false value.
Returns the value of the last EXPR it evaluates.

Perl equivalent:

  EXPR1 && EXPR2 && ...

=item {\or EXPR1 EXPR2 ...}

Evaluates each EXPR in turn, stopping if one yields a true value.
Returns the true value if there is one, falsehood otherwise.

Perl equivalent:

  EXPR1 || EXPR2 || ...

=item {\cond {TEST1 THEN1a THEN1b ...} {TEST2 THEN2a THEN2b ...} ...}

Evaluates each TEST in turn.  If one yields a true value, evaluates
the corresponding THENs in sequence and returns the value of the last
one.

Perl equivalent:

  if (TEST1) {
    THEN1a;
    THEN1b;
    ...
  } elsif (TEST2) {
    THEN2a;
    THEN2b;
    ...
  } ...

=item {\while TEST EXPR1 EXPR2 ...}

Evaluates TEST.  If it's true, evaluates EXPR1 through EXPRn and
starts again.

Perl correspondence:

  while (TEST) {
    EXPR1;
    EXPR2;
    ...
  }

=item {\lambda {PARAM1 PARAM2 ...} EXPR1 EXPR2 ...}

Creates an anonymous subroutine.  When the subroutine is invoked, its
arguments will be assigned to the parameters PARAM1, PARAM2, etc., and
the EXPRs evaluated in the resulting context.  The value will be the
value of the last EXPR.

Each PARAM is one of the following:

=over 4

=item \VAR

An ordinary variable reference.  This creates a I<positional
parameter>.

=item \=VAR

This is a I<named parameter>.

=item \&VAR

This is a I<rest parameter>.  There may be at most one of these.

=back

See below for how to invoke Blatte subroutines, and how argument
parsing proceeds.

Perl equivalent:

  sub {
    ...(argument parsing)...
    EXPR1;
    EXPR2;
    ...
  }

=item {\define {\NAME PARAM1 PARAM2 ...} EXPR1 EXPR2 ...}

Defines a subroutine and assigns it to the variable \NAME.  This is
shorthand for

  {\define \NAME {\lambda {PARAM1 PARAM2 ...} EXPR1 EXPR2 ...}}

=item {\let {{\VAR1 VAL1} {\VAR2 VAL2} ...} EXPR1 EXPR2 ...}

Evaluates the VALs, then assigns them to the vars, then evaluates the
EXPRs in the resulting context, returning the value of the last one.

Perl equivalence:

  {
    my($VAR1, $VAR2, ...) = (VAL1, VAL2, ...);

    EXPR1;
    EXPR2;
    ...
  }

=item {\let* {{\VAR1 VAL1} {\VAR2 VAL2} ...} EXPR1 EXPR2 ...}

Like \let, but each VAL is assigned to its \VAR as soon as it's
computed, so later VALs can refer to earlier \VARs.

Perl equivalence:

  {
    my $VAR1 = VAL1;
    my $VAR2 = VAL2;
    ...

    EXPR1;
    EXPR2;
    ...
  }

=item {\letrec {{\VAR1 VAL1} {\VAR2 VAL2} ...} EXPR1 EXPR2 ...}

Like \let and \let*, but evaluates all the VALs in a context where the
VARs have been declared but not yet assigned.  This allows them to
refer to one another by reference.

Perl equivalence:

  {
    my($VAR1, $VAR2, ...);

    ($VAR1, $VAR2, ...) = (VAL1, VAL2, ...);

    EXPR1;
    EXPR2;
    ...
  }

=item {EXPR1 EXPR2 ... EXPRn}

A sequence of one or more expressions enclosed in curly braces that
isn't one of the expression types listed above is either a function
call or a plain list.

If the value of EXPR1 is a Blatte subroutine, it is a function call,
and the values of EXPR2 through EXPRn are passed as arguments.  In
this case it corresponds to the following Perl:

  &{EXPR1}({ ...named parameter hash... }, ...other arguments...)

See below for an explanation of Blatte subroutine argument parsing.

If EXPR1 isn't a Blatte subroutine, then

  {EXPR1 EXPR2 ... EXPRn}

is a plain list whose elements are the values of EXPR1 through EXPRn.
Blatte lists correspond to Perl array references:

  [EXPR1, EXPR2, ..., EXPRn]

=item Delimited string

A Blatte string begins and ends with \" (\"sample\").  It may contain
any characters, including whitespace.  \ must be escaped like this:
\\.  Note, however, that " is I<not> escaped.

=item WORD

Anything that contains no whitespace, isn't one of the above
expression types, and escapes any instances of Blatte's three
metacharacters, is a word.

=back

In addition to the expression types above, there are two additional
pieces of Blatte syntax:

=over 4

=item \;

This introduces a comment, which continues to the end of the line.

=item \/

This is the "forget-whitespace" operator.  It cancels any whitespace
immediately preceding it.  See the section on Whitespace handling
below.

=back

=head2 Argument parsing for function calls

As mentioned above, Blatte subroutines (a.k.a. functions) have three
kinds of parameters: positional, named, and rest.

When calling a Blatte function, named parameters can be given values
by writing

  \NAME=EXPR

where \NAME is the parameter (which was given as \=NAME in the
function definition).

All remaining arguments in the function call are assigned to
positional parameters in the order in which they were declared.  If
there aren't enough positional parameters, then all the remaining
arguments are collected in a Blatte list and assigned to the rest
parameter.

When a Blatte function call is translated to Perl, the named parameter
assignments are collected together in an anonymous HASH reference,
which is passed as the first argument to the Perl subroutine
corresponding to the Blatte function.  (All Blatte functions are Perl
subroutines that accept this anonymous HASH reference of named
parameters as a first argument.)  All remaining Blatte arguments are
passed in sequence to the Perl subroutine.

Inside the Perl subroutine, arguments are unpacked as follows: named
parameters are extracted from the HASH reference and assigned to
correspondingly named Perl variables; Perl variables for the
positional parameters get the next N arguments from @_; and the
remainder of @_ is turned into an ARRAY reference (a Blatte list) and
assigned to the Perl variable denoting the rest parameter.

Example:

  {\define {\fn \=n1 \=n2 \a \b \&r}
    ...do stuff...}

becomes:

  $fn = sub {
    my($_named, $a, $b) = splice(@_, 0, 3);
    my $n1 = $_named->{n1};
    my $n2 = $_named->{n2};
    my $r = \@_;

    ...do stuff...
  };

and the function call

  {\fn \n2=17 This is an example.}

becomes:

  &$fn({n2 => 17}, 'This', 'is', 'an', 'example.')

which means $n1 will be undef, $n2 will be 17, $a will be 'This', $b
will be 'is', and $r will be ['an', 'example'].

(Almost.  This example ignores Blatte's whitespace handling, which is
explained below.)

=head2 Whitespace handling

Before recognizing a Blatte expression, the Blatte parser skips over a
(possibly empty) sequence of whitespace.  This whitespace is
preserved; then, when the parser is finished, the result is wrapped in
a Blatte::Ws object, or a "whitespace wrapper," containing the
preserved whitespace and the parsed expression.  In this way, the
whitespace preceding each expression is carried along with the
expression itself.  When Blatte expressions are parsed, evaluated, and
rendered normally (see flatten() below), the output preserves the same
whitespace found in the input.

=head1 FUNCTIONS

=over 4

=item Parse(INPUT)

Parses the first Blatte expression in INPUT using the default parser.
The result is converted to a string of Perl code and returned.

(If you don't use the default parser, it's possible to change Blatte's
syntax, to obtain the intermediate parse tree before conversion to
Perl, and more.  See L<Blatte::Parser(3)>.)

INPUT is either a string containing Blatte code, or a reference to
such a string.  If it's a reference, then after a successful parse,
the matched expression will be removed from the beginning of the
referenced string.

=item traverse(OBJ, CALLBACK, [WS])

Walks the data structure OBJ.  If OBJ is an ARRAY reference, its
elements are recursively traversed.  If OBJ is a whitespace wrapper,
its contents are recursively traversed.  Otherwise, CALLBACK (a Perl
CODE reference) is invoked on WS and OBJ.  WS is a string of
whitespace, possibly empty.

CALLBACK should return truth if it uses its whitespace argument and
falsehood if it doesn't (meaning that traverse() should reuse the
whitespace value in subsequent calls, if necessary).  "Uses" usually
means that the whitespace is copied to some sort of output.

This function supplies the logic that causes outer whitespace wrappers
to take precedence over inner ones.

=item flatten(OBJ, [WS])

Renders OBJ as a string, with optional leading whitespace WS (which
takes precedence over any outermost whitespace wrapper that might be
present).

This function is written in terms of traverse().

=item wrapws(WS, OBJ)

Creates a new whitespace wrapper whose whitespace string is WS and
whose nested object is OBJ.

=item unwrapws(OBJ)

Unwraps as many layers of whitespace wrapper from OBJ as necessary to
reach a non-wrapper object, then returns that.

=item wsof(OBJ)

This returns the whitespace string, possibly empty, associated with
OBJ.  Note that

  wsof(wrapws(X, Y))

is always X, however

  unwrapws(wrapws(X, Y))

is Y only when Y is not itself a whitespace wrapper.

=item true(OBJ)

Returns the Blatte truth value of OBJ (after whitespace-unwrapping,
see above).  As in Perl, 0 and the empty string are false, but so is
an empty Blatte list (that is, a Perl ARRAY ref with zero elements);
all other values are true.

=item quote(STRING)

Quote STRING using Blatte syntax so that it can be read back as a
Blatte string literal.

=back

=head1 PEDIGREE

Blatte is a successor to an earlier language called Latte.  The B is
for "better" -- better because, whereas Latte's runtime facilities
were fairly limited, Blatte's are effectively unlimited, since Blatte
has the full power of Perl at its disposal.  The implementation is
also much faster and simpler than that of Latte.  Latte users should
beware that, despite being substantially similar, the Blatte language
has significant differences from Latte.

The design of the Blatte language was strongly influenced by Scheme,
and was guided by these principles:

=over 4

=item *

The syntax should be simple, terse, and unobtrusive.

=item *

There should be as few metacharacters as possible (contrast TeX), so
as to have minimum impact on mostly textual Blatte documents.

=item *

The language should be fully general, not a half-hearted macro system
that makes many computations impossible.

=item *

The correspondence between the source language (Blatte) and the target
language (Perl) should be simple and direct.

=back

=head1 DEDICATION

Blatte is dedicated to the memory of Julie Epelboim, 1964-2001.  Not
that she ever would have used it.  This was a woman who preferred to
write I<raw Postscript code> rather than use a page layout program.
The tragedy of having lost her is dwarfed by the good fortune of
having known her.

=head1 AUTHOR

Bob Glickstein <bobg@zanshin.com>.

Visit the Blatte website, <http://www.blatte.org/>.

=head1 LICENSE

Copyright 2001 Bob Glickstein.  All rights reserved.

Blatte is distributed under the terms of the GNU General Public
License, version 2.  See the file LICENSE that accompanies the Blatte
distribution.

=head1 SEE ALSO

L<Blatte::Compiler(3)>, L<Blatte::Builtins(3)>, L<Blatte::Parser(3)>,
L<Blatte::Ws(3)>.
