package SQL::Tiny;

use 5.010001;
use strict;
use warnings;

=head1 NAME

SQL::Tiny - A very simple SQL-building library

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

use parent 'Exporter';

our @EXPORT_OK = qw(
    sql_select
    sql_insert
    sql_update
    sql_delete
);


=head1 SYNOPSIS

    my ($sql,$bind) = sql_select( 'users', [ 'name', 'status' ], { status => [ 'Deleted', 'Inactive' ] );

    my ($sql,$bind) = sql_insert( 'users', { name => 'Dave', status => 'Active' } );

    my ($sql,$bind) = sql_update( 'users', { status => 'Inactive' }, { password => undef } );

    my ($sql,$bind) = sql_delete( 'users', { status => 'Inactive' } );

=head1 DOCUMENTATION

A very simple SQL-building library.  It's not for all your SQL needs,
only the very simple ones.

It doesn't handle JOINs.  It doesn't handle GROUP BY.  It doens't handle
subselects.  It's only for simple SQL.

In my test suites, I have a lot of ad hoc SQL queries, and it drives me
nuts to have so much SQL code lying around.  SQL::Tiny is for generating
SQL code for simple cases.

I'd far rather have:

    my ($sql,$binds) = sql_insert(
        'users',
        {
            name      => 'Dave',
            salary    => 50000,
            status    => 'Active',
            dateadded => \'SYSDATE()',
        }
    );

than hand-coding:

    my $sql   = 'INSERT INTO users (name,salary,status,dateadded) VALUES (:name,:status,:salary,SYSDATE())';
    my $binds = {
        ':name'      => 'Dave',
        ':salary'    => 50000,
        ':status'    => 'Active',
        ':dateadded' => \'SYSDATE()',
    };

or even the positional:

    my $sql   = 'INSERT INTO users (name,salary,status,dateadded) VALUES (?,?,?,SYSDATE())';
    my $binds = [ 'Dave', 50000, 'Active' ];

The trade-off for that brevity of code is that SQL::Tiny has to make new
SQL and binds from the input every time. You can't cache the SQL that
comes back from SQL::Tiny because the placeholders could vary depending
on what the input data is. Therefore, you don't want to use SQL::Tiny
where speed is essential.

The other trade-off is that SQL::Tiny handles only very simple code.
It won't handle JOINs of any kind.

SQL::Tiny isn't meant for all of your SQL needs, only the simple ones
that you do over and over.

=head1 EXPORT

All subs can be exported, but none are by default.

=head1 SUBROUTINES/METHODS

=head2 sql_select( $table, \@columns, \%where [, \%other ] )

Creates simple SELECTs and binds.

Calling:

    my ($sql,$binds) = sql_select(
        'users',
        [qw( userid name )],
        { status => 'X' ],
        { order_by => 'name' },
    );

returns:

    $sql   = 'SELECT userid,name FROM users WHERE status=? ORDER BY name';
    $binds = [ 'X' ];

=cut

sub sql_select {
    my $table   = shift;
    my $columns = shift;
    my $where   = shift;
    my $other   = shift // {};

    my @parts = (
        'SELECT ' . join( ',', @{$columns} ),
        "FROM $table",
    );

    my @binds;
    my @where_conditions;

    _build_where( $where, \@where_conditions, \@binds );

    if ( @where_conditions ) {
        push @parts, 'WHERE ' . join( ' AND ', @where_conditions );
    }

    if ( my $order = $other->{order_by} ) {
        if ( ref($order) eq 'ARRAY' ) {
            push @parts, 'ORDER BY ' . join( ',', @{$order} );
        }
        else {
            push @parts, "ORDER BY $order";
        }
    }

    my $sql = join( ' ', @parts );

    return ( $sql, \@binds );
}


=head2 sql_insert( $table, \%values )

Creates simple INSERTs and binds.

Calling:

    my ($sql,$binds) = sql_insert(
        'users',
        {
            serialno   => '12345',
            name       => 'Dave',
            rank       => 'Sergeant',
            height     => undef,
            date_added => \'SYSDATE()',
        }
    );

returns:

    $sql   = 'INSERT INTO users (date_added,height,name,rank,serialno) VALUES (SYSDATE(),NULL,?,?,?)';
    $binds = [ 'Dave', 'Sergeant', 12345 ]

=cut

sub sql_insert {
    my $table  = shift;
    my $values = shift;

    my @parts = (
        "INSERT INTO $table"
    );

    my @columns;
    my @values;
    my @binds;

    for my $key ( sort keys %{$values} ) {
        my $value = $values->{$key};

        push @columns, $key;
        if ( !defined($value) ) {
            push @values, 'NULL';
        }
        elsif ( ref($value) eq 'SCALAR' ) {
            push @values, ${$value};
        }
        else {
            push @values, '?';
            push @binds, $value;
        }
    }

    push @parts, '(' . join( ',', @columns ) . ')';
    push @parts, 'VALUES (' . join( ',', @values ) . ')';
    my $sql = join( ' ', @parts );

    return ( $sql, \@binds );
}


=head2 sql_update( $table, \%values, \%where )

Creates simple UPDATE calls and binds.

Calling:

    my ($sql,$binds) = sql_update(
        'users',
        {
            status     => 'X',
            lockdate   => undef,
        },
        {
            orderdate => \'SYSDATE()',
        },
    );

returns:

    $sql   = 'UPDATE users SET lockdate=NULL, status=? WHERE orderdate=SYSDATE()'
    $binds = [ 'X' ]

=cut

sub sql_update {
    my $table  = shift;
    my $values = shift;
    my $where  = shift;

    my @parts = (
        "UPDATE $table"
    );

    my @columns;
    my @where_conditions;
    my @binds;

    for my $key ( sort keys %{$values} ) {
        my $value = $values->{$key};

        if ( !defined($value) ) {
            push @columns, "$key=NULL";
        }
        elsif ( ref($value) eq 'SCALAR' ) {
            push @columns, "$key=${$value}";
        }
        else {
            push @columns, "$key=?";
            push @binds, $value;
        }
    }
    push @parts, 'SET ' . join( ', ', @columns );

    _build_where( $where, \@where_conditions, \@binds );

    if ( @where_conditions ) {
        push @parts, 'WHERE ' . join( ' AND ', @where_conditions );
    }

    my $sql = join( ' ', @parts );

    return ( $sql, \@binds );
}


=head2 sql_delete( $table, \%where )

Creates simple DELETE calls and binds.

Calling:

    my ($sql,$binds) = sql_delete(
        'users',
        {
            serialno   => 12345,
            height     => undef,
            date_added => \'SYSDATE()',
            status     => [qw( X Y Z )],
        },
    );

returns:

    $sql   = 'DELETE FROM users WHERE date_added = SYSDATE() AND height IS NULL AND serialno = ? AND status IN (?,?,?)'
    $binds = [ 12345, 'X', 'Y', 'Z' ]

=cut

sub sql_delete {
    my $table = shift;
    my $where = shift;

    my @parts = (
        "DELETE FROM $table"
    );

    my @where_conditions;
    my @binds;

    _build_where( $where, \@where_conditions, \@binds );

    if ( @where_conditions ) {
        push @parts, 'WHERE ' . join( ' AND ', @where_conditions );
    }

    my $sql = join( ' ', @parts );

    return ( $sql, \@binds );
}


sub _build_where {
    my $where      = shift;
    my $conditions = shift;
    my $binds      = shift;

    for my $key ( sort keys %{$where} ) {
        my $value = $where->{$key};
        if ( !defined($value) ) {
            push @{$conditions}, "$key IS NULL";
        }
        elsif ( ref($value) eq 'ARRAY' ) {
            push @{$conditions}, "$key IN (" . join( ',', ('?') x @{$value} ) . ')';
            push @{$binds}, @{$value};
        }
        elsif ( ref($value) eq 'SCALAR' ) {
            push @{$conditions}, "$key=${$value}";
        }
        else {
            push @{$conditions}, "$key=?";
            push @{$binds}, $value;
        }
    }

    return;
}


=head1 AUTHOR

Andy Lester, C<< <andy at petdance.com> >>

=head1 BUGS

Please report any bugs or feature requests to
L<https://github.com/petdance/sql-simple/issues>, or email me directly.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc SQL::Tiny

You can also look for information at:

=over 4

=item * MetaCPAN

L<https://metacpan.org/release/SQL-Tiny>

=item * GitHub issue tracker

L<https://github.com/petdance/sql-simple/issues>

=back

=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright 2019 Andy Lester.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

=cut

1; # End of SQL::Tiny
