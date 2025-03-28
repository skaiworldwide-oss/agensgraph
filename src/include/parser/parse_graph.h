/*
 * parse_graph.h
 *	  handle clauses for graph in parser
 *
 * Copyright (c) 2016 by Bitnine Global, Inc.
 *
 * IDENTIFICATION
 *	  src/include/parser/parse_graph.h
 */

#ifndef PARSE_GRAPH_H
#define PARSE_GRAPH_H

#include "parser/parse_node.h"

#define AGENS_DEFAULT_PREFIX	"_agens_default_"
#define CYPHER_SUBQUERY_ALIAS	AGENS_DEFAULT_PREFIX"s"
#define CYPHER_OPTMATCH_ALIAS	AGENS_DEFAULT_PREFIX"o"
#define CYPHER_MERGEMATCH_ALIAS	AGENS_DEFAULT_PREFIX"m"
#define CYPHER_DELETEJOIN_ALIAS	AGENS_DEFAULT_PREFIX"d"

extern bool enable_eager;

extern Query *transformCypherSubPattern(ParseState *pstate,
										CypherSubPattern *subpat);
extern Query *transformCypherProjection(ParseState *pstate,
										CypherClause *clause);
extern Query *transformCypherMatchClause(ParseState *pstate,
										 CypherClause *clause);
extern Query *transformCypherCreateClause(ParseState *pstate,
										  CypherClause *clause);
extern Query *transformCypherDeleteClause(ParseState *pstate,
										  CypherClause *clause);
extern Query *transformCypherSetClause(ParseState *pstate,
									   CypherClause *clause);
extern Query *transformCypherMergeClause(ParseState *pstate,
										 CypherClause *clause);
extern Query *transformCypherLoadClause(ParseState *pstate,
										CypherClause *clause);
extern Query *transformCypherUnwindClause(ParseState *pstate,
										  CypherClause *clause);

#endif							/* PARSE_GRAPH_H */
