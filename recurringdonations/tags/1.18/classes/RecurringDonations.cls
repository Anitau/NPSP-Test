/*
	Copyright (c) 2009, Salesforce.com Foundation
	All rights reserved.
	
	Redistribution and use in source and binary forms, with or without
	modification, are permitted provided that the following conditions are met:
	
	* Redistributions of source code must retain the above copyright
	  notice, this list of conditions and the following disclaimer.
	* Redistributions in binary form must reproduce the above copyright
	  notice, this list of conditions and the following disclaimer in the
	  documentation and/or other materials provided with the distribution.
	* Neither the name of the Salesforce.com Foundation nor the names of
	  its contributors may be used to endorse or promote products derived
  	  from this software without specific prior written permission.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
	"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
	LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
	FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
	COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
	INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
	LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
	CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
	LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN 
	ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
	POSSIBILITY OF SUCH DAMAGE.
*/
global class RecurringDonations {

	/// <name> RecurringDonations </name>
	/// <summary> Default Constructor </summary>
	public RecurringDonations(){}


	/// <name> triggerAction </name>
	/// <summary> contains possible actions for a trigger </summary>
	public enum triggerAction {beforeInsert, beforeUpdate, beforeDelete, afterInsert, afterUpdate, afterDelete, afterUndelete}


	/// <name> RecurringDonations </name>
	/// <summary> Overloads the RecurringDonations object constructor to handle RecurringDonation processing </summary>
	/// <param name="recurringDonations"> RecurringDonation objects that are being triggered </param>
	/// <param name="oldRecurringDonations"> RecurringDonation object values before trigger event </param>
	/// <param name="ta"> Trigger action that is occuring </param>
	public RecurringDonations(Recurring_Donation__c[] recurringDonations, Recurring_Donation__c[] oldRecurringDonations, triggerAction ta)
	{
		List<Recurring_Donation__c> contactRecDonations = new List<Recurring_Donation__c>();
		List<Recurring_Donation__c> accountRecDonations = new List<Recurring_Donation__c>();
		List<Recurring_Donation__c> recDonationDeletes = new List<Recurring_Donation__c>();

		for(Recurring_Donation__c r : recurringDonations)
		{
			if (ta==triggerAction.beforeInsert)
			{
				if (r.Organization__c == null && r.Contact__c == null)
				{
					r.addError(System.Label.RecurringDonationMissingDataError);
				}
				if ( r.Installments__c > 50 )
				{
					r.addError(System.Label.RecurringDonationTooManyInstallmentsError);
				}
			}
			if ( ta==triggerAction.afterInsert )
			{
				if (r.Contact__c != null)
				{
					contactRecDonations.add(r);
				} else
				{
					accountRecDonations.add(r);
				}
			}
			if ( ta==triggerAction.beforeDelete )
			{
				recDonationDeletes.add(r);
			}
		}

		if ( contactRecDonations.size() > 0 )
		{
			insertOpptys(contactRecDonations, 'contact');
		}
		if ( accountRecDonations.size() > 0 )
		{
			insertOpptys(accountRecDonations, 'account');
		}
		if ( recDonationDeletes.size() > 0 )
		{
			deleteRecDonations(recDonationDeletes);
		}
	}
	
	/// <name> insertContactOpportunities </name>
	/// <summary> Creates new Opportunities when a RecurringDonation is inserted </summary>
	/// <param name="recurringDonations"> RecurringDonation objects that are being triggered </param>
	public static void insertOpptys( Recurring_Donation__c[] recurringDonations, String donorType )
	{
		
		
		//Lists used for final Insert
		List<Opportunity> opportunityInserts = new List<Opportunity>();
		List<OpportunityContactRole> contactRoleInserts = new List<OpportunityContactRole>();

		//Create a list of ContactIds used in these RecurringDonations
		List<Id> contactIds = new List<Id>();
		Map<Id,Id> recConMap = new Map<Id,Id>();
		for( Recurring_Donation__c r : recurringDonations )
		{
			if ( r.Contact__c != null )
			{
				contactIds.add(r.Contact__c);
				recConMap.put(r.Id,r.Contact__c);
			}
		}

		//Create a Map of Contact Ids and Contact Records
		Map<Id,Contact> contactMap;
		Map<Id,Account> accountMap;
		if ( contactIds.size() > 0 )
		{
			contactMap = new Map<Id,Contact>([Select Id, AccountId from Contact where Id in :contactIds and AccountId != null]);
		}


		//Loop through the Recurring Donations and create the appropriate number of Opportunities
		for(Recurring_Donation__c r : recurringDonations)
		{
			Decimal installs = Decimal.valueOf(r.Installments__c);
			Integer installments = installs.intValue();
				
			for ( Integer j=0;j<installments;j++ )
			{
				Opportunity opp = new Opportunity();
				
				if ( r.Organization__c != null )
				{
					opp.AccountId = r.Organization__c;
				}
				else
				if ( contactMap.containsKey(r.Contact__c) )
				{
					Contact c = contactMap.get(r.Contact__c);
					opp.AccountId = c.AccountId;
				}
				//add the remainder to the last installment, otherwise use the amount
				if (j + 1 == installments && installments * r.Installment_Amount__c != r.Total__c)
				{
					opp.Amount = r.Total__c - (j * r.Installment_Amount__c);
				} else {
					opp.Amount = r.Installment_Amount__c;
				}
				
				if (r.Installment_Period__c == 'Yearly')
				{
					opp.CloseDate = (r.Date_Established__c).addYears(j);
				} else
				if (r.Installment_Period__c == 'Quarterly')
				{
					opp.CloseDate = (r.Date_Established__c).addMonths(3*j);
				} else
				if (r.Installment_Period__c == 'Monthly')
				{
					opp.CloseDate = (r.Date_Established__c).addMonths(j);
				} else
				if (r.Installment_Period__c == 'Weekly')
				{
					opp.CloseDate = (r.Date_Established__c).addDays(7*j);
				} else
				{
					opp.CloseDate = (r.Date_Established__c);
				}
				
				String oName = '';
				oName += r.Donor_Name__c; 
				oName += ' ';
				oName += System.Label.RecurringDonationPrefix;
				oName += ' (';
				oName += j+1;
				oName += ' of ';
				oName += installments;
				oName += ') ';
				oName += opp.CloseDate.format();
				opp.Name = oName;
				
				opp.StageName = System.Label.RecurringDonationStageName;
				opp.Recurring_Donation__c = r.Id;
				opportunityInserts.add(opp);
				if ( opportunityInserts.size() == 100 )
				{
					Database.SaveResult[] lsr = Database.insert(opportunityInserts, false);
					opportunityInserts.clear();
				}
			}
		}
		
		if( opportunityInserts.size() > 0 )
		{
			Database.SaveResult[] lsr = Database.insert(opportunityInserts, false);
			Integer i = 0;
   	        for (Database.SaveResult s : lsr)
       	    {
            	if ( s.isSuccess() == true )
   	        	{
       	    		OpportunityContactRole ocr = new OpportunityContactRole();
           			ocr.OpportunityId = s.getId();
           			ocr.Role = System.Label.RecurringDonationContactRole;
            		ocr.IsPrimary = true;
					if ( recConMap.containsKey(opportunityInserts[i].Recurring_Donation__c) )
					{
	           			ocr.ContactId = recConMap.get(opportunityInserts[i].Recurring_Donation__c);
   		        		contactRoleInserts.add(ocr);
						if ( contactRoleInserts.size() == 100 )
						{
							Database.SaveResult[] osr = Database.insert(contactRoleInserts, false);
							contactRoleInserts.clear();
						}
					}
       	    	}
           		i++;
			}
			if ( contactRoleInserts.size() > 0 )
			{
				Database.SaveResult[] osr = Database.insert(contactRoleInserts, false);
			}
		}
	}
	

	/// <name> deleteRecDonations </name>
	/// <summary> Validates that a Recurring Donation can be deleted </summary>
	/// <param name="recurringDonations"> RecurringDonation objects that are being triggered </param>
	public static void deleteRecDonations(Recurring_Donation__c[] recurringDonations)
	{
		Map<Id,Id> recDonationMap = new Map<Id,Id>();
		List<Id> recDonationIds = new List<Id>();
		
		for(Recurring_Donation__c r : recurringDonations)
		{
			recDonationIds.add(r.Id);
		}
		for (Opportunity o : [Select Id, Recurring_Donation__c from Opportunity where Recurring_Donation__c in :recDonationIds])
		{
			recDonationMap.put(o.Recurring_Donation__c,o.Id);
		}
		for(Recurring_Donation__c r : recurringDonations)
		{
			if(recDonationMap.containsKey(r.Id))
			{
				r.addError(System.Label.RecurringDonationCantDeleteError);
			}
		}
	}
	
}